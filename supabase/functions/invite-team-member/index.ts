import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Authenticate caller
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const body = await req.json() as { email?: string };
    const email = body.email?.trim().toLowerCase();

    if (!email) {
      return new Response(JSON.stringify({ error: 'email is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Get caller's team — must be the owner
    const { data: team, error: teamError } = await supabase
      .from('teams')
      .select('id, seat_limit')
      .eq('owner_id', user.id)
      .maybeSingle();

    if (teamError || !team) {
      return new Response(JSON.stringify({ error: 'Not a team owner' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Count active members (owner counts against limit too)
    const { count } = await supabase
      .from('team_members')
      .select('id', { count: 'exact', head: true })
      .eq('team_id', team.id)
      .eq('status', 'active');

    if ((count ?? 0) >= (team.seat_limit - 1)) {
      // seat_limit includes the owner, so members can fill seat_limit - 1 slots
      return new Response(JSON.stringify({ error: 'Seat limit reached' }), {
        status: 422,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Upsert pending invitation
    const { error: insertError } = await supabase
      .from('team_members')
      .upsert(
        { team_id: team.id, email, role: 'member', status: 'pending' },
        { onConflict: 'team_id,email', ignoreDuplicates: false },
      );

    if (insertError) {
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Send invite email via Resend (optional — skip if key not configured)
    const resendKey = Deno.env.get('RESEND_API_KEY');
    if (resendKey) {
      const deepLink =
        `tradeestimateai://team/join?team_id=${team.id}&email=${encodeURIComponent(email)}`;

      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${resendKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'Trade Estimate AI <noreply@tradeestimateai.com>',
          to: [email],
          subject: "You've been invited to a Trade Estimate AI team",
          html: `<p>You've been invited to join a Trade Estimate AI team.</p>
                 <p><a href="${deepLink}">Tap here to accept the invitation</a></p>
                 <p>Or open the Trade Estimate AI app and use the link above.</p>`,
        }),
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
