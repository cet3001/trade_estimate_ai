import { createClient } from 'npm:@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Startup guard: fail fast if required env vars are absent rather than
// silently creating a broken client with empty-string credentials.
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  throw new Error('Missing required env vars: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
}
// adminClient instantiated once at module scope, not per-request.
const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

// Escape user-supplied strings before interpolating them into the XML prompt
// block. Without this, a value like "</job_description><system>inject</system>"
// would break out of its wrapper and manipulate the model's context.
function escapeXml(value: unknown): string {
  if (typeof value !== 'string') return '';
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ─── Auth ─────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const jwt = authHeader.replace(/^Bearer\s+/i, '');
    const { data: { user }, error: authError } = await adminClient.auth.getUser(jwt);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ─── Parse Request Body ────────────────────────────────────────────────
    const {
      trade,
      jobTitle,
      jobDescription,
      scopeDetails,
      laborHours,
      laborRate,
      materialsCost,
      additionalFees,
      clientName,
      clientEmail,
      jobLocation,
      notes,
      businessName,
      licenseNumber,
      contractorName,
    } = await req.json();

    // ─── Input Validation (Fix 3) ──────────────────────────────────────────
    const tradeContext: Record<string, string> = {
      plumbing: `You are writing a professional plumbing estimate for a licensed plumber. Use industry-standard plumbing terminology. Reference pipe types, fixture brands, and code compliance where appropriate. Mention cleanup and site protection.`,
      electrical: `You are writing a professional electrical estimate for a licensed electrician. Reference NEC code compliance, permit requirements, and safety standards. Use electrical terminology (panels, circuits, breakers, conduit, gauge).`,
      roofing: `You are writing a professional roofing estimate for a licensed roofing contractor. Reference material quality, manufacturer warranties, underlayment, flashing, and proper disposal of old materials.`,
      construction: `You are writing a professional construction estimate for a general contractor. Reference building code compliance, subcontractor coordination, site safety, material sourcing, and project milestones.`,
    };

    if (!trade || !tradeContext[trade]) {
      return new Response(
        JSON.stringify({ error: 'Invalid or missing trade' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
    if (!jobTitle || !jobDescription) {
      return new Response(
        JSON.stringify({ error: 'jobTitle and jobDescription are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Input length limits
    const MAX_JOB_TITLE = 200;
    const MAX_JOB_DESCRIPTION = 5000;
    const MAX_NOTES = 2000;
    if (jobTitle.length > MAX_JOB_TITLE || jobDescription.length > MAX_JOB_DESCRIPTION || (notes && notes.length > MAX_NOTES)) {
      return new Response(
        JSON.stringify({ error: 'Input exceeds maximum allowed length' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
    if (typeof laborHours !== 'number' || typeof laborRate !== 'number' || typeof materialsCost !== 'number') {
      return new Response(
        JSON.stringify({ error: 'laborHours, laborRate, and materialsCost must be numbers' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ─── Fetch Profile ─────────────────────────────────────────────────────
    const { data: profile, error: profileError } = await adminClient
      .from('profiles')
      .select('credits_remaining, subscription_status, is_admin')
      .eq('id', user.id)
      .single();

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ error: 'Profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const hasSubscription = profile.subscription_status === 'active';
    const isAdmin = profile.is_admin === true;
    const hasCredits = profile.credits_remaining > 0;

    // ─── Check Entitlements ────────────────────────────────────────────────
    if (!hasSubscription && !isAdmin && !hasCredits) {
      return new Response(
        JSON.stringify({ error: 'No credits remaining', code: 'NO_CREDITS' }),
        { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ─── Atomic Credit Deduction BEFORE Anthropic Call ────────────────────
    // Credit is deducted atomically before calling the AI to prevent a TOCTOU race
    // condition (two concurrent requests both passing the initial credits check).
    // If the Anthropic call or DB insert subsequently fails, the credit is consumed
    // without a saved estimate. This is an accepted trade-off; a credit refund path
    // (add_one_credit RPC) should be added if this becomes a user-reported issue.
    //
    // deduct_one_credit uses WHERE credits_remaining > 0, so it is race-safe.
    // Returns true on success, false if another concurrent request consumed
    // the last credit first.
    if (!hasSubscription && !isAdmin) {
      const { data: deducted, error: deductError } = await adminClient.rpc('deduct_one_credit', { p_user_id: user.id });
      if (deductError) {
        console.error('Credit deduction error:', deductError);
        return new Response(
          JSON.stringify({ error: 'Failed to deduct credit' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      if (!deducted) {
        return new Response(
          JSON.stringify({ error: 'No credits remaining', code: 'NO_CREDITS' }),
          { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // ─── Build Estimate Arithmetic ─────────────────────────────────────────
    const totalEstimate =
      (laborHours * laborRate) + materialsCost + (additionalFees || 0);

    // ─── Call Anthropic ────────────────────────────────────────────────────
    // Fix 2: Static instructions go in `system`; user-supplied content is
    // wrapped in XML tags to prevent prompt injection.
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!anthropicKey) {
      return new Response(
        JSON.stringify({ error: 'AI service not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const anthropic = new Anthropic({ apiKey: anthropicKey });
    let message;
    try {
    message = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 1000,
      system: `${tradeContext[trade] || tradeContext.construction}

Write a professional written estimate for the following job. This will be sent directly to a client as a formal business document. Write the estimate body only. Do not include a cost table. Do not include headers. Write in professional paragraphs covering: what work will be performed, how it will be performed, materials to be used, timeline expectation, what is included, and what is excluded. End with a professional closing statement referencing the total and inviting the client to ask questions. Maximum 400 words.`,
      messages: [{
        role: 'user',
        content: `<contractor>${escapeXml(contractorName || businessName || '')}</contractor>
<business>${escapeXml(businessName || '')}</business>
${licenseNumber ? `<license>${escapeXml(licenseNumber)}</license>` : ''}
<client>${escapeXml(clientName || '')}</client>
${clientEmail ? `<client_email>${escapeXml(clientEmail)}</client_email>` : ''}
<job_title>${escapeXml(jobTitle)}</job_title>
${jobLocation ? `<location>${escapeXml(jobLocation)}</location>` : ''}
<trade>${trade.charAt(0).toUpperCase() + trade.slice(1)}</trade>
<job_description>${escapeXml(jobDescription)}</job_description>
${scopeDetails ? `<scope_details>${escapeXml(JSON.stringify(scopeDetails, null, 2))}</scope_details>` : ''}
<cost_breakdown>
- Labor: ${laborHours} hours at $${laborRate}/hour = $${(laborHours * laborRate).toFixed(2)}
- Materials: $${Number(materialsCost).toFixed(2)}
- Additional Fees: $${Number(additionalFees || 0).toFixed(2)}
- Total: $${totalEstimate.toFixed(2)}
</cost_breakdown>
${notes ? `<notes>${escapeXml(notes)}</notes>` : ''}`
      }],
    });

    } catch (aiError: unknown) {
      // Refund credit on Anthropic failure (429 rate limit or other)
      if (!hasSubscription && !isAdmin) {
        try {
          await adminClient.rpc('increment_credits', { user_id: user.id, amount: 1 });
        } catch (refundErr) {
          console.error('Credit refund failed:', refundErr);
        }
      }
      const status = (aiError as { status?: number })?.status;
      if (status === 429) {
        return new Response(
          JSON.stringify({ error: 'AI service is temporarily busy. Please try again in a moment.' }),
          { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      throw aiError;
    }

    const estimateBody =
      message.content[0].type === 'text' ? message.content[0].text : '';

    // ─── Save Estimate ─────────────────────────────────────────────────────
    const { data: estimate, error: insertError } = await adminClient
      .from('estimates')
      .insert({
        user_id: user.id,
        trade,
        client_name: clientName,
        client_email: clientEmail || null,
        job_title: jobTitle,
        job_description: jobDescription,
        scope_of_work: JSON.stringify(scopeDetails ?? {}),
        scope_details: scopeDetails ?? {},
        labor_hours: laborHours,
        labor_rate: laborRate,
        materials_cost: materialsCost,
        additional_fees: additionalFees || 0,
        total_estimate: totalEstimate,
        ai_generated_body: estimateBody,
        status: 'draft',
      })
      .select()
      .single();

    if (insertError) {
      console.error('Insert error:', insertError);
      return new Response(
        JSON.stringify({ error: 'Failed to save estimate' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ─── Increment Estimates Counter (Fix 5: log error, don't fail) ────────
    const { error: incrError } = await adminClient.rpc('increment_estimates_generated', { p_user_id: user.id });
    if (incrError) console.error('Failed to increment estimates counter:', incrError);

    return new Response(
      JSON.stringify({ estimate }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
