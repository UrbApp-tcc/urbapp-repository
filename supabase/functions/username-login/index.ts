const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const jsonResponse = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {...corsHeaders, 'Content-Type': 'application/json'},
  });

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }

  if (request.method !== 'POST') {
    return jsonResponse({error: 'Método não permitido.'}, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({error: 'Serviço de autenticação indisponível.'}, 503);
  }

  let payload: {username?: unknown; password?: unknown};
  try {
    payload = await request.json();
  } catch (_) {
    return jsonResponse({error: 'Dados de login inválidos.'}, 400);
  }

  const username = typeof payload.username === 'string'
    ? payload.username.trim().replace(/^@+/, '')
    : '';
  const password = typeof payload.password === 'string' ? payload.password : '';

  if (username.length < 3 || username.length > 80 || password.length < 6) {
    return jsonResponse({error: 'Nome de usuário ou senha inválidos.'}, 401);
  }

  const serviceHeaders = {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    'Content-Type': 'application/json',
  };

  let profileId: string | null = null;
  try {
    const lookupResponse = await fetch(
      `${supabaseUrl}/rest/v1/rpc/find_profile_id_by_username`,
      {
        method: 'POST',
        headers: serviceHeaders,
        body: JSON.stringify({login_username: username}),
      },
    );

    if (lookupResponse.ok) {
      profileId = await lookupResponse.json();
    }
  } catch (_) {
    return jsonResponse({error: 'Serviço de autenticação indisponível.'}, 503);
  }

  let email = 'invalid-login@urbapp.invalid';
  if (profileId) {
    try {
      const userResponse = await fetch(
        `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(profileId)}`,
        {headers: serviceHeaders},
      );
      if (userResponse.ok) {
        const user = await userResponse.json();
        if (typeof user.email === 'string' && user.email.trim().length > 0) {
          email = user.email.trim();
        }
      }
    } catch (_) {
      return jsonResponse({error: 'Serviço de autenticação indisponível.'}, 503);
    }
  }

  const tokenResponse = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: {
        apikey: anonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({email, password}),
    },
  );

  if (!tokenResponse.ok) {
    if (tokenResponse.status === 429) {
      return jsonResponse(
        {error: 'Muitas tentativas. Aguarde um pouco e tente novamente.'},
        429,
      );
    }
    return jsonResponse({error: 'Nome de usuário ou senha inválidos.'}, 401);
  }

  return jsonResponse(await tokenResponse.json(), 200);
});
