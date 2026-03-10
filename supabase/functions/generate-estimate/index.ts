// REQUIRED VAULT SECRETS:
//   ANTHROPIC_API_KEY       — Anthropic API key
//   SUPABASE_URL            — Supabase project URL (auto-set by platform)
//   SUPABASE_SERVICE_ROLE_KEY — Supabase service role key
//   SUPABASE_ANON_KEY       — Supabase anon/public key
//
// IMPORTANT: SUPABASE_ANON_KEY must be explicitly added to the Supabase vault
// alongside the others. It is NOT automatically injected into edge function
// environment by all Supabase hosting configurations. Without it, JWT-based
// user verification inside this function will fail.

import Anthropic from 'npm:@anthropic-ai/sdk';
import { createClient } from 'npm:@supabase/supabase-js@2';

function sanitizePromptField(s: unknown, maxLen: number): string {
  if (typeof s !== 'string') return '';
  return s
    .trim()
    .slice(0, maxLen)
    .replace(/\n(system|assistant|human|user):/gi, ' ')
    .replace(/\n---/g, ' ');
}

Deno.serve(async (req) => {
  try {
    // 1. Authenticate the request via JWT
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 2. Parse request body — return 400 on malformed JSON
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const {
      trade,
      clientName,
      clientEmail,
      jobTitle,
      jobDescription,
      scopeDetails,
      laborHours,
      laborRate,
      materialsCost,
      additionalFees,
      jobLocation,
      notes,
      businessName,
      licenseNumber,
    } = body;

    // 3. Build trade-specific prompt context (must be defined before validation
    //    so the trade lookup works in the validation block below)
    const tradeContexts: Record<string, string> = {
      plumbing: `You are writing a professional plumbing estimate for a licensed plumber. Use industry-standard plumbing terminology. Reference pipe types, fixture brands, and code compliance where appropriate. Mention cleanup and site protection.`,
      electrical: `You are writing a professional electrical estimate for a licensed electrician. Reference NEC code compliance, permit requirements, and safety standards. Use electrical terminology (panels, circuits, breakers, conduit, gauge).`,
      roofing: `You are writing a professional roofing estimate for a licensed roofing contractor. Reference material quality, manufacturer warranties, underlayment, flashing, and proper disposal of old materials.`,
      construction: `You are writing a professional construction estimate for a general contractor. Reference building code compliance, subcontractor coordination, site safety, material sourcing, and project milestones.`,
    };

    // 4. Validate required fields
    if (!trade || !jobTitle || !jobDescription ||
        typeof laborHours !== 'number' || typeof laborRate !== 'number' ||
        typeof materialsCost !== 'number') {
      return new Response(JSON.stringify({ error: 'Missing or invalid required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (!tradeContexts[trade as string]) {
      return new Response(JSON.stringify({ error: `Unsupported trade: ${trade}` }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 5. Create Supabase admin client to read/write DB with service role
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // 6. Verify user identity from JWT
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user }, error: userError } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 7. Fetch profile — distinguish a real DB error (500) from a missing row
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('subscription_status, credits_remaining')
      .eq('id', user.id)
      .single();

    if (profileError && profileError.code !== 'PGRST116') {
      return new Response(JSON.stringify({ error: 'Failed to load profile' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (!profile) {
      return new Response(
        JSON.stringify({ error: 'Profile not found. Please complete onboarding.' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const hasSubscription = profile?.subscription_status === 'active';

    // 8. Atomically deduct a credit (or skip for active subscribers).
    //    deduct_one_credit performs a conditional UPDATE in a single statement,
    //    eliminating the check-then-act race condition.
    if (!hasSubscription) {
      const { data: deducted, error: rpcError } = await supabaseAdmin
        .rpc('deduct_one_credit', { p_user_id: user.id });
      if (rpcError) {
        return new Response(JSON.stringify({ error: 'Failed to check credits' }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      if (!deducted) {
        return new Response(
          JSON.stringify({ error: 'No credits or active subscription' }),
          { status: 402, headers: { 'Content-Type': 'application/json' } }
        );
      }
    }

    // 9. Build prompt and call Anthropic API
    const laborTotal = (laborHours as number) * (laborRate as number);
    const totalEstimate = laborTotal + (materialsCost as number) + ((additionalFees as number) ?? 0);

    const sBusinessName = sanitizePromptField(businessName, 100);
    const sLicenseNumber = sanitizePromptField(licenseNumber, 50);
    const sClientName = sanitizePromptField(clientName, 100);
    const sJobTitle = sanitizePromptField(jobTitle, 200);
    const sJobLocation = sanitizePromptField(jobLocation, 200);
    const sJobDescription = sanitizePromptField(jobDescription, 1000);
    const sNotes = sanitizePromptField(notes, 500);

    const prompt = `${tradeContexts[trade as string]}

Write a professional written estimate for the following job. This will be sent directly to a client as a formal business document.

Business: ${sBusinessName}${sLicenseNumber ? ` | License #${sLicenseNumber}` : ''}
Client: ${sClientName}
Job Title: ${sJobTitle}
Location: ${sJobLocation || 'Not specified'}
Trade: ${(trade as string).charAt(0).toUpperCase() + (trade as string).slice(1)}

Job Description: ${sJobDescription}

Scope Details:
${Object.entries((scopeDetails as Record<string, unknown>) ?? {}).map(([k, v]) => `- ${sanitizePromptField(k, 100)}: ${sanitizePromptField(v, 500)}`).join('\n')}

Cost Breakdown:
- Labor: ${laborHours} hours at $${laborRate}/hour = $${laborTotal.toFixed(2)}
- Materials: $${(materialsCost as number).toFixed(2)}
- Additional Fees: $${((additionalFees as number) ?? 0).toFixed(2)}
- Total: $${totalEstimate.toFixed(2)}

${sNotes ? `Notes/Exclusions: ${sNotes}` : ''}

Write the estimate body only. Do not include the cost table (that will be added separately). Do not include headers like "Estimate" or "Scope of Work". Write in flowing professional paragraphs. Cover: what work will be performed, how it will be performed, materials to be used, timeline expectation, what is included, and what is excluded. End with a professional closing statement referencing the total and inviting the client to ask questions. Maximum 400 words. Use confident, professional language. No filler phrases.`;

    const anthropic = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY') });
    const message = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 1000,
      messages: [{ role: 'user', content: prompt }],
    });

    const estimateBody =
      message.content[0].type === 'text' ? message.content[0].text : '';

    // 10. Save estimate to DB
    // scope_of_work (TEXT) receives a JSON string for backward compatibility;
    // scope_details (JSONB) receives the parsed object so Flutter can read it
    // as Map<String, dynamic> via Estimate.fromJson.
    const { data: estimate, error: insertError } = await supabaseAdmin
      .from('estimates')
      .insert({
        user_id: user.id,
        trade,
        client_name: clientName,
        client_email: clientEmail,
        job_title: jobTitle,
        job_description: jobDescription,
        scope_of_work: JSON.stringify(scopeDetails ?? {}),
        scope_details: scopeDetails ?? {},
        labor_hours: laborHours,
        labor_rate: laborRate,
        materials_cost: materialsCost,
        additional_fees: additionalFees ?? 0,
        total_estimate: totalEstimate,
        ai_generated_body: estimateBody,
        status: 'draft',
      })
      .select()
      .single();

    if (insertError) {
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 11. Increment total_estimates_generated counter
    await supabaseAdmin.rpc('increment_estimates_generated', { p_user_id: user.id });

    return new Response(JSON.stringify({ estimate }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
