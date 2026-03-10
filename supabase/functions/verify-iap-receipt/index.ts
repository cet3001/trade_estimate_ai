import { createClient } from 'npm:@supabase/supabase-js@2';

// App Store product identifiers
const PRODUCT_SUBSCRIPTION = 'com.blackstonerow.tradeestimateai.subscription.monthly';
const PRODUCT_CREDITS_5 = 'com.blackstonerow.tradeestimateai.credits.5';
const PRODUCT_CREDITS_15 = 'com.blackstonerow.tradeestimateai.credits.15';

Deno.serve(async (req) => {
  try {
    // 1. Authenticate
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 2. Parse body — return 400 on malformed JSON
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const { transaction_id, product_id, user_id } = body;

    if (!transaction_id || !product_id || !user_id) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 3. Create admin client for privileged DB operations
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // 4. Verify user identity from JWT and confirm the JWT matches user_id
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user }, error: userError } = await supabaseUser.auth.getUser();
    if (userError || !user || user.id !== user_id) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 5. Idempotency check — prevent a transaction from being processed twice
    const { data: existing } = await supabaseAdmin
      .from('iap_receipts')
      .select('id')
      .eq('transaction_id', transaction_id)
      .single();

    if (existing) {
      return new Response(JSON.stringify({ already_processed: true }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 6. Validate product_id before writing anything
    if (
      product_id !== PRODUCT_SUBSCRIPTION &&
      product_id !== PRODUCT_CREDITS_5 &&
      product_id !== PRODUCT_CREDITS_15
    ) {
      return new Response(
        JSON.stringify({ error: `Unknown product_id: ${product_id}` }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // 7. Store receipt record (transaction_id column has a UNIQUE constraint).
    //    Check for insert errors — if this fails, do not grant entitlements.
    const { error: insertError } = await supabaseAdmin.from('iap_receipts').insert({
      user_id,
      product_id,
      transaction_id,
      purchase_date: new Date().toISOString(),
      is_active: true,
    });
    if (insertError) {
      return new Response(JSON.stringify({ error: 'Failed to store receipt' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 8. Grant entitlement based on product — check each grant for errors
    if (product_id === PRODUCT_SUBSCRIPTION) {
      const { error: grantError } = await supabaseAdmin
        .from('profiles')
        .update({ subscription_status: 'active' })
        .eq('id', user_id);
      if (grantError) {
        return new Response(JSON.stringify({ error: 'Failed to grant subscription' }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    } else if (product_id === PRODUCT_CREDITS_5) {
      const { error: grantError } = await supabaseAdmin.rpc('add_credits', { p_user_id: user_id, p_amount: 5 });
      if (grantError) {
        return new Response(JSON.stringify({ error: 'Failed to grant credits' }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    } else if (product_id === PRODUCT_CREDITS_15) {
      const { error: grantError } = await supabaseAdmin.rpc('add_credits', { p_user_id: user_id, p_amount: 15 });
      if (grantError) {
        return new Response(JSON.stringify({ error: 'Failed to grant credits' }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
