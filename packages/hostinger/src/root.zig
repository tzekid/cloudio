const net_http = @import("net_http");
const client = @import("client.zig");

pub const Client = client.Client;
pub const Response = net_http.Response;
pub const models = @import("provider_hostinger_models");
pub const routes = @import("provider_hostinger_routes");

test {
    _ = Client;
    _ = Response;
    _ = models;
    _ = routes;
}
