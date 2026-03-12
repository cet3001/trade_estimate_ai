import { createClient } from 'npm:@supabase/supabase-js@2'
import { SignJWT, importPKCS8, decodeJwt } from 'npm:jose@5'

const BUNDLE_ID = 'com.blackstonerow.tradeestimateai'
const VALID_PRODUCT_IDS = new Set([
  'com.blackstonerow.tradeestimateai.subscription.monthly',
  'com.blackstonerow.tradeestimateai.credits.5c',
  'com.blackstonerow.tradeestimateai.credits.15',
  'com.blackstonerow.tradeestimateai.subscription.team3',
  'com.blackstonerow.tradeestimateai.subscription.team5',
])

const APPLE_PRODUCTION_URL = 'https://api.storekit.itunes.apple.com'
const APPLE_SANDBOX_URL = 'https://api.storekit-sandbox.itunes.apple.com'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

async function generateAppleJWT(): Promise<string> {
  const keyId = Deno.env.get('APPLE_KEY_ID')!
  const issuerId = Deno.env.get('APPLE_ISSUER_ID')!
  const privateKeyPem = Deno.env.get('APPLE_PRIVATE_KEY')!

  const privateKey = await importPKCS8(privateKeyPem, 'ES256')

  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
    .setIssuer(issuerId)
    .setIssuedAt()
    .setExpirationTime('1h')
    .setAudience('appstoreconnect-v1')
    .sign(privateKey)

  return jwt
}

async function verifyWithApple(
  transactionId: string,
  jwt: string,
  useSandbox = false
): Promise<Record<string, unknown>> {
  const baseUrl = useSandbox ? APPLE_SANDBOX_URL : APPLE_PRODUCTION_URL
  const url = `${baseUrl}/inApps/v1/transactions/${transactionId}`

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${jwt}`,
    },
  })

  if (!response.ok) {
    throw new Error(`Apple API error: ${response.status} ${await response.text()}`)
  }

  const data = await response.json()
  // The signedTransactionInfo is a JWS — decode the payload (no signature verification needed
  // since we fetched it directly from Apple's API over TLS)
  const signedTransaction = data.signedTransactionInfo as string
  const transactionPayload = decodeJwt(signedTransaction) as Record<string, unknown>
  return transactionPayload
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Auth check
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { transaction_id, product_id } = await req.json()

    if (!transaction_id || !product_id) {
      return new Response(
        JSON.stringify({ error: 'Missing transaction_id or product_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!VALID_PRODUCT_IDS.has(product_id)) {
      return new Response(
        JSON.stringify({ error: 'Invalid product_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Idempotency check — return success if already verified
    const { data: existing } = await supabase
      .from('iap_receipts')
      .select('id')
      .eq('transaction_id', transaction_id)
      .eq('user_id', user.id)
      .maybeSingle()

    if (existing) {
      return new Response(
        JSON.stringify({ success: true, already_verified: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Generate Apple JWT and verify transaction
    const appleJwt = await generateAppleJWT()
    let transactionInfo: Record<string, unknown>
    let environment = 'Production'

    try {
      transactionInfo = await verifyWithApple(transaction_id, appleJwt, false)
    } catch (_prodError) {
      // Fall back to sandbox
      try {
        transactionInfo = await verifyWithApple(transaction_id, appleJwt, true)
        environment = 'Sandbox'
      } catch (sandboxError) {
        throw new Error(`Transaction verification failed: ${sandboxError.message}`)
      }
    }

    // Validate bundle ID
    if (transactionInfo.bundleId !== BUNDLE_ID) {
      return new Response(
        JSON.stringify({ error: 'Bundle ID mismatch' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate product ID matches
    if (transactionInfo.productId !== product_id) {
      return new Response(
        JSON.stringify({ error: 'Product ID mismatch' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check for revocation
    if (transactionInfo.revocationDate) {
      return new Response(
        JSON.stringify({ error: 'Transaction has been revoked' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Insert receipt with TOCTOU protection via unique constraint
    const { error: insertError } = await supabase
      .from('iap_receipts')
      .insert({
        user_id: user.id,
        transaction_id,
        product_id,
        environment,
        verified_at: new Date().toISOString(),
        purchase_date: transactionInfo.purchaseDate
          ? new Date(transactionInfo.purchaseDate as number).toISOString()
          : new Date().toISOString(),
      })

    if (insertError) {
      // 23505 = unique_violation — race condition, already inserted
      if (insertError.code === '23505') {
        return new Response(
          JSON.stringify({ success: true, already_verified: true }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      throw new Error(`Failed to store receipt: ${insertError.message}`)
    }

    // Grant entitlement based on product
    const SUBSCRIPTION_PRODUCTS = new Set([
      'com.blackstonerow.tradeestimateai.subscription.monthly',
      'com.blackstonerow.tradeestimateai.subscription.team3',
      'com.blackstonerow.tradeestimateai.subscription.team5',
    ])

    if (SUBSCRIPTION_PRODUCTS.has(product_id)) {
      const expiresMs = transactionInfo.expiresDate as number | undefined
      const subscribedUntil = expiresMs
        ? new Date(expiresMs).toISOString()
        : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()

      await supabase
        .from('profiles')
        .update({
          subscription_status: 'active',
          subscription_product_id: product_id,
          subscription_expires_at: subscribedUntil,
        })
        .eq('id', user.id)
    } else {
      // Credits product
      const creditsMap: Record<string, number> = {
        'com.blackstonerow.tradeestimateai.credits.5c': 5,
        'com.blackstonerow.tradeestimateai.credits.15': 15,
      }
      const credits = creditsMap[product_id] ?? 0
      if (credits > 0) {
        await supabase.rpc('increment_credits', { user_id: user.id, amount: credits })
      }
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('verify-iap-receipt error:', error)
    return new Response(
      JSON.stringify({ error: error.message ?? 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
