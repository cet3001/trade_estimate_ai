import { createClient } from 'npm:@supabase/supabase-js@2';

// Escapes HTML special characters to prevent XSS when interpolating
// user-controlled strings into HTML email content.
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

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

    const { estimate_id, recipient_email, recipient_name } = body;

    if (!estimate_id || !recipient_email) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Basic email format validation
    if (!(recipient_email as string).includes('@')) {
      return new Response(JSON.stringify({ error: 'Invalid recipient email' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 3. Create clients
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    );

    // 4. Verify user identity from JWT
    const { data: { user }, error: userError } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 5. Fetch estimate and profile in parallel; enforce ownership via user_id filter
    const [
      { data: estimate, error: estError },
      { data: profile, error: profError },
    ] = await Promise.all([
      supabaseAdmin
        .from('estimates')
        .select('*')
        .eq('id', estimate_id)
        .eq('user_id', user.id)
        .single(),
      supabaseAdmin
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single(),
    ]);

    if (estError || !estimate) {
      return new Response(JSON.stringify({ error: 'Estimate not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    if (profError || !profile) {
      return new Response(JSON.stringify({ error: 'Profile not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 6. Build HTML email
    const html = buildEmailHtml(estimate, profile, (recipient_name as string) ?? '');

    // 7. Send via Resend
    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
      },
      body: JSON.stringify({
        from: 'estimates@tradeestimateai.com',
        to: recipient_email,
        subject: `Estimate from ${profile.company_name ?? profile.full_name}: ${estimate.job_title}`,
        html,
      }),
    });

    if (!resendRes.ok) {
      const resendError = await resendRes.text();
      return new Response(
        JSON.stringify({ error: `Resend error: ${resendError}` }),
        { status: 502, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // 8. Update estimate status to 'sent'; re-assert ownership with user_id filter
    await supabaseAdmin
      .from('estimates')
      .update({ status: 'sent', sent_at: new Date().toISOString() })
      .eq('id', estimate_id)
      .eq('user_id', user.id);

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

function buildEmailHtml(
  estimate: Record<string, unknown>,
  profile: Record<string, unknown>,
  recipientName: string
): string {
  const businessName = escapeHtml(
    (profile.company_name ?? profile.full_name ?? 'Your Contractor') as string
  );
  const phone = profile.phone as string | null;
  const email = profile.email as string;
  const license = profile.license_number as string | null;
  const emailSignature = (profile.email_signature as string | null)?.trim() || null;

  const laborTotal = (
    (estimate.labor_hours as number) * (estimate.labor_rate as number)
  ).toFixed(2);
  const materialsTotal = (estimate.materials_cost as number).toFixed(2);
  const additionalFeesFormatted = (estimate.additional_fees as number).toFixed(2);
  const totalEstimate = (estimate.total_estimate as number).toFixed(2);

  // Mirror the standardTradeTerms constant from AppStrings, with business name substituted
  const terms =
    `This estimate is valid for 30 days from the date of issue. ` +
    `Payment terms: 50% deposit due upon acceptance, remaining balance due upon project completion. ` +
    `${businessName} is not responsible for hidden conditions discovered during work that require ` +
    `additional materials or labor. Any changes to the scope of work will be documented in a ` +
    `written change order and may affect the final price. Work is warranted for one year from ` +
    `completion date. This estimate does not include permit fees unless explicitly stated above.`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;background-color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f5f5f5;padding:24px 0;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;overflow:hidden;max-width:600px;">

        <!-- Header -->
        <tr><td style="background-color:#0F0F0F;padding:24px 32px;">
          <p style="margin:0;font-size:20px;font-weight:700;color:#ffffff;">${businessName}</p>
          <p style="margin:4px 0 0;font-size:13px;color:#8E8E93;">${phone ? `${escapeHtml(phone)}  |  ` : ''}${escapeHtml(email)}${license ? `  |  License #${escapeHtml(license)}` : ''}</p>
        </td></tr>

        <!-- Prepared For -->
        <tr><td style="padding:24px 32px 16px;border-bottom:1px solid #e5e5e5;">
          <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#8E8E93;letter-spacing:0.8px;text-transform:uppercase;">Prepared For</p>
          <p style="margin:0;font-size:17px;font-weight:600;color:#0F0F0F;">${escapeHtml(recipientName || (estimate.client_name as string))}</p>
          <p style="margin:2px 0 0;font-size:14px;color:#636366;">${escapeHtml(estimate.client_email as string)}</p>
        </td></tr>

        <!-- Estimate Body -->
        <tr><td style="padding:24px 32px;">
          <p style="margin:0 0 8px;font-size:11px;font-weight:600;color:#8E8E93;letter-spacing:0.8px;text-transform:uppercase;">Estimate — ${escapeHtml(estimate.job_title as string)}</p>
          <p style="margin:0;font-size:14px;line-height:1.6;color:#1C1C1E;">${escapeHtml(estimate.ai_generated_body as string).replace(/\n/g, '<br>')}</p>
        </td></tr>

        <!-- Cost Summary -->
        <tr><td style="padding:0 32px 24px;">
          <table width="100%" cellpadding="6" cellspacing="0" style="border-top:1px solid #e5e5e5;">
            <tr>
              <td colspan="2" style="font-size:11px;font-weight:600;color:#8E8E93;letter-spacing:0.8px;text-transform:uppercase;padding-top:16px;">Cost Summary</td>
            </tr>
            <tr>
              <td style="font-size:14px;color:#1C1C1E;">Labor (${estimate.labor_hours}h &times; $${estimate.labor_rate}/hr)</td>
              <td align="right" style="font-size:14px;color:#1C1C1E;font-family:monospace;">$${laborTotal}</td>
            </tr>
            <tr>
              <td style="font-size:14px;color:#1C1C1E;">Materials</td>
              <td align="right" style="font-size:14px;color:#1C1C1E;font-family:monospace;">$${materialsTotal}</td>
            </tr>
            ${
              parseFloat(additionalFeesFormatted) > 0
                ? `<tr>
              <td style="font-size:14px;color:#1C1C1E;">Additional Fees</td>
              <td align="right" style="font-size:14px;color:#1C1C1E;font-family:monospace;">$${additionalFeesFormatted}</td>
            </tr>`
                : ''
            }
            <tr style="border-top:2px solid #0F0F0F;">
              <td style="font-size:16px;font-weight:700;color:#0F0F0F;padding-top:10px;">TOTAL</td>
              <td align="right" style="font-size:16px;font-weight:700;color:#34C759;font-family:monospace;padding-top:10px;">$${totalEstimate}</td>
            </tr>
          </table>
        </td></tr>

        <!-- Terms & Conditions -->
        <tr><td style="padding:0 32px 24px;border-top:1px solid #e5e5e5;">
          <p style="margin:16px 0 4px;font-size:11px;font-weight:600;color:#8E8E93;letter-spacing:0.8px;text-transform:uppercase;">Terms &amp; Conditions</p>
          <p style="margin:0;font-size:11px;line-height:1.5;color:#8E8E93;">${terms}</p>
        </td></tr>

        <!-- Signature (only if set) -->
        ${emailSignature ? `
        <tr><td style="padding:0 32px 24px;">
          <p style="margin:0;font-size:13px;line-height:1.6;color:#1C1C1E;white-space:pre-line;">${escapeHtml(emailSignature)}</p>
        </td></tr>` : ''}

        <!-- Footer -->
        <tr><td style="padding:16px 32px;background-color:#f5f5f5;border-top:1px solid #e5e5e5;">
          <p style="margin:0;font-size:11px;color:#8E8E93;text-align:center;">
            Questions about this estimate? Reply to this email.<br>
            Sent via <strong>Trade Estimate AI</strong>
          </p>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;
}
