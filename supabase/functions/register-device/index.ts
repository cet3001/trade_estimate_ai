import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  // Verify user is authenticated
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Missing authorization' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // Create service role client for DB operations
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

  // Verify the JWT and get user
  const userClient = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: { user }, error: authError } = await userClient.auth.getUser()
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const body = await req.json()
  const { device_id, device_name } = body as { device_id: string; device_name?: string }

  if (!device_id) {
    return new Response(JSON.stringify({ error: 'device_id required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // Upsert device session, updating last_seen to mark this as the active device
  const { error } = await supabase
    .from('device_sessions')
    .upsert(
      {
        user_id: user.id,
        device_id,
        device_name: device_name ?? null,
        last_seen: new Date().toISOString(),
      },
      { onConflict: 'user_id,device_id' }
    )

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  return new Response(JSON.stringify({ ok: true, device_id }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
