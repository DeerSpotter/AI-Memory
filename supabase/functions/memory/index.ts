import { createClient } from "@supabase/supabase-js";

type JsonRecord = Record<string, unknown>;

type MemoryRequest = {
  action: string;
  project_id?: string;
  session_id?: string;
  name?: string;
  title?: string;
  content?: string;
  summary?: string;
  query?: string;
  tags?: string[];
  decisions?: string[];
  open_tasks?: string[];
  files_discussed?: string[];
  next_steps?: string[];
  metadata?: JsonRecord;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Missing required field: ${field}`);
  }
  return value.trim();
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Use POST" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");

  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: "Supabase environment is not configured" }, 500);
  }

  if (!authorization) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authorization
      }
    }
  });

  const body = (await req.json()) as MemoryRequest;
  const action = requireString(body.action, "action");

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    switch (action) {
      case "create_project": {
        const name = requireString(body.name, "name");
        const { data, error } = await supabase
          .from("memory_projects")
          .insert({
            name,
            description: typeof body.content === "string" ? body.content : null,
            metadata: body.metadata ?? {}
          })
          .select()
          .single();

        if (error) throw error;
        return jsonResponse({ project: data });
      }

      case "list_projects": {
        const { data, error } = await supabase
          .from("memory_projects")
          .select("id,name,description,status,repo_url,metadata,created_at,updated_at")
          .order("updated_at", { ascending: false });

        if (error) throw error;
        return jsonResponse({ projects: data ?? [] });
      }

      case "create_session": {
        const project_id = requireString(body.project_id, "project_id");
        const title = requireString(body.title ?? body.name, "title");
        const { data, error } = await supabase
          .from("memory_sessions")
          .insert({
            project_id,
            title,
            source: "app",
            metadata: body.metadata ?? {}
          })
          .select()
          .single();

        if (error) throw error;
        return jsonResponse({ session: data });
      }

      case "save_memory": {
        const project_id = requireString(body.project_id, "project_id");
        const title = requireString(body.title, "title");
        const content = requireString(body.content, "content");
        const { data, error } = await supabase
          .from("memory_items")
          .insert({
            project_id,
            source_session_id: body.session_id ?? null,
            title,
            content,
            tags: asStringArray(body.tags),
            metadata: body.metadata ?? {}
          })
          .select()
          .single();

        if (error) throw error;
        return jsonResponse({ memory: data });
      }

      case "search_memory": {
        const project_id = requireString(body.project_id, "project_id");
        const query = requireString(body.query, "query");
        const pattern = `%${query.replaceAll("%", "\\%").replaceAll("_", "\\_")}%`;

        const { data, error } = await supabase
          .from("memory_items")
          .select("id,project_id,title,content,tags,importance,is_pinned,created_at,updated_at")
          .eq("project_id", project_id)
          .or(`title.ilike.${pattern},content.ilike.${pattern}`)
          .order("is_pinned", { ascending: false })
          .order("importance", { ascending: false })
          .order("updated_at", { ascending: false })
          .limit(20);

        if (error) throw error;
        return jsonResponse({ memories: data ?? [] });
      }

      case "save_session_summary": {
        const project_id = requireString(body.project_id, "project_id");
        const summary = requireString(body.summary ?? body.content, "summary");
        const { data, error } = await supabase
          .from("memory_session_summaries")
          .insert({
            project_id,
            session_id: body.session_id ?? null,
            summary,
            decisions: asStringArray(body.decisions),
            open_tasks: asStringArray(body.open_tasks),
            files_discussed: asStringArray(body.files_discussed),
            next_steps: asStringArray(body.next_steps),
            metadata: body.metadata ?? {}
          })
          .select()
          .single();

        if (error) throw error;
        return jsonResponse({ session_summary: data });
      }

      case "get_project_context": {
        const project_id = requireString(body.project_id, "project_id");

        const [projectResult, summariesResult, memoriesResult, artifactsResult] = await Promise.all([
          supabase
            .from("memory_projects")
            .select("id,name,description,status,repo_url,metadata,updated_at")
            .eq("id", project_id)
            .single(),
          supabase
            .from("memory_session_summaries")
            .select("id,summary,decisions,open_tasks,files_discussed,next_steps,importance,created_at")
            .eq("project_id", project_id)
            .order("created_at", { ascending: false })
            .limit(5),
          supabase
            .from("memory_items")
            .select("id,title,content,tags,importance,is_pinned,updated_at")
            .eq("project_id", project_id)
            .order("is_pinned", { ascending: false })
            .order("importance", { ascending: false })
            .order("updated_at", { ascending: false })
            .limit(25),
          supabase
            .from("memory_artifacts")
            .select("id,name,artifact_type,url_or_path,notes,created_at")
            .eq("project_id", project_id)
            .order("created_at", { ascending: false })
            .limit(10)
        ]);

        if (projectResult.error) throw projectResult.error;
        if (summariesResult.error) throw summariesResult.error;
        if (memoriesResult.error) throw memoriesResult.error;
        if (artifactsResult.error) throw artifactsResult.error;

        return jsonResponse({
          project: projectResult.data,
          summaries: summariesResult.data ?? [],
          memories: memoriesResult.data ?? [],
          artifacts: artifactsResult.data ?? []
        });
      }

      default:
        return jsonResponse({ error: `Unknown action: ${action}` }, 400);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 400);
  }
});
