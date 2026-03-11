import { createClient } from 'npm:@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

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

    // Extract the JWT and verify it using the service role admin client.
    // Using adminClient.auth.getUser(jwt) is more reliable in Edge Functions
    // than the anon-key pattern because SUPABASE_SERVICE_ROLE_KEY is
    // explicitly set in the vault and always present.
    const jwt = authHeader.replace(/^Bearer\s+/i, '');
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: { user }, error: authError } = await adminClient.auth.getUser(jwt);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ─── Check Entitlements ────────────────────────────────────────────────
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

    if (!hasSubscription && !isAdmin && !hasCredits) {
      return new Response(
        JSON.stringify({ error: 'No credits remaining', code: 'NO_CREDITS' }),
        { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
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

    // ─── Build Estimate ────────────────────────────────────────────────────
    const tradeContext: Record<string, string> = {
      plumbing: `You are writing a professional plumbing estimate for a licensed plumber. Use industry-standard plumbing terminology. Reference pipe types, fixture brands, and code compliance where appropriate. Mention cleanup and site protection.`,
      electrical: `You are writing a professional electrical estimate for a licensed electrician. Reference NEC code compliance, permit requirements, and safety standards. Use electrical terminology (panels, circuits, breakers, conduit, gauge).`,
      roofing: `You are writing a professional roofing estimate for a licensed roofing contractor. Reference material quality, manufacturer warranties, underlayment, flashing, and proper disposal of old materials.`,
      construction: `You are writing a professional construction estimate for a general contractor. Reference building code compliance, subcontractor coordination, site safety, material sourcing, and project milestones.`,
    };

    const totalEstimate =
      (laborHours * laborRate) + materialsCost + (additionalFees || 0);

    const prompt = `
${tradeContext[trade] || tradeContext.construction}

Write a professional written estimate for the following job.
This will be sent directly to a client as a formal business document.

Contractor: ${contractorName || businessName}
Business: ${businessName} ${licenseNumber ? `| License #${licenseNumber}` : ''}
Client: ${clientName}
${clientEmail ? `Client Email: ${clientEmail}` : ''}
Job Title: ${jobTitle}
${jobLocation ? `Location: ${jobLocation}` : ''}
Trade: ${trade.charAt(0).toUpperCase() + trade.slice(1)}

Job Description: ${jobDescription}

${scopeDetails ? `Scope Details:\n${JSON.stringify(scopeDetails, null, 2)}` : ''}

Cost Breakdown:
- Labor: ${laborHours} hours at $${laborRate}/hour = $${(laborHours * laborRate).toFixed(2)}
- Materials: $${Number(materialsCost).toFixed(2)}
- Additional Fees: $${Number(additionalFees || 0).toFixed(2)}
- Total: $${totalEstimate.toFixed(2)}

${notes ? `Notes/Exclusions: ${notes}` : ''}

Write the estimate body only. Do not include a cost table. Do not include headers. Write in professional paragraphs covering: what work will be performed, how it will be performed, materials to be used, timeline expectation, what is included, and what is excluded. End with a professional closing statement referencing the total and inviting the client to ask questions. Maximum 400 words.
    `.trim();

    // ─── Call Anthropic ────────────────────────────────────────────────────
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!anthropicKey) {
      return new Response(
        JSON.stringify({ error: 'AI service not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const anthropic = new Anthropic({ apiKey: anthropicKey });
    const message = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 1000,
      messages: [{ role: 'user', content: prompt }],
    });

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
        JSON.stringify({ error: 'Failed to save estimate', details: insertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ─── Deduct Credit ─────────────────────────────────────────────────────
    if (!hasSubscription && !isAdmin) {
      await adminClient.rpc('deduct_one_credit', { p_user_id: user.id });
    }

    // Increment total estimates generated
    await adminClient.rpc('increment_estimates_generated', { p_user_id: user.id });

    return new Response(
      JSON.stringify({ estimate }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
