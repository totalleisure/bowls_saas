import { handleRequest } from "./handler.ts";
Deno.serve((req) => handleRequest(req, (name) => Deno.env.get(name)));
