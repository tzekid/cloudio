const std = @import("std");
const net_http = @import("net_http");
pub const transport = @import("provider_hostinger_transport");
pub const routes = @import("provider_hostinger_routes");
pub const models = @import("provider_hostinger_models");
const hostinger_transport = transport;

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const base_url = routes.base_url;
pub const virtual_machines_path = routes.virtual_machines_path;
pub const data_centers_path = routes.data_centers_path;
pub const firewall_path = routes.firewall_path;
pub const public_keys_path = routes.public_keys_path;
pub const templates_path = routes.templates_path;
pub const post_install_scripts_path = routes.post_install_scripts_path;
pub const billing_catalog_path = routes.billing_catalog_path;
pub const billing_payment_methods_path = routes.billing_payment_methods_path;
pub const billing_subscriptions_path = routes.billing_subscriptions_path;
pub const dns_zones_path = routes.dns_zones_path;
pub const dns_snapshots_path = routes.dns_snapshots_path;
pub const domains_availability_path = routes.domains_availability_path;
pub const domains_portfolio_path = routes.domains_portfolio_path;
pub const domains_forwarding_path = routes.domains_forwarding_path;
pub const domains_whois_path = routes.domains_whois_path;
pub const hosting_accounts_path = routes.hosting_accounts_path;
pub const hosting_datacenters_path = routes.hosting_datacenters_path;
pub const hosting_domains_path = routes.hosting_domains_path;
pub const hosting_orders_path = routes.hosting_orders_path;
pub const hosting_websites_path = routes.hosting_websites_path;
pub const hosting_wordpress_installations_path = routes.hosting_wordpress_installations_path;
pub const ecommerce_stores_path = routes.ecommerce_stores_path;
pub const horizons_websites_path = routes.horizons_websites_path;
pub const reach_contacts_path = routes.reach_contacts_path;
pub const reach_profiles_path = routes.reach_profiles_path;
pub const reach_segments_path = routes.reach_segments_path;

pub const VmEndpoint = routes.VmEndpoint;
pub const VpsMutationEndpoint = routes.VpsMutationEndpoint;
pub const VpsMutationArgs = routes.VpsMutationArgs;
pub const VpsInventoryEndpoint = routes.VpsInventoryEndpoint;
pub const VpsInventoryDetailEndpoint = routes.VpsInventoryDetailEndpoint;
pub const VpsResourceMutationEndpoint = routes.VpsResourceMutationEndpoint;
pub const VpsResourceMutationArgs = routes.VpsResourceMutationArgs;
pub const FirewallMutationEndpoint = routes.FirewallMutationEndpoint;
pub const FirewallMutationArgs = routes.FirewallMutationArgs;
pub const DockerEndpoint = routes.DockerEndpoint;
pub const DockerMutationEndpoint = routes.DockerMutationEndpoint;
pub const DockerMutationArgs = routes.DockerMutationArgs;
pub const BillingEndpoint = routes.BillingEndpoint;
pub const BillingMutationEndpoint = routes.BillingMutationEndpoint;
pub const BillingMutationArgs = routes.BillingMutationArgs;
pub const DnsEndpoint = routes.DnsEndpoint;
pub const DnsMutationEndpoint = routes.DnsMutationEndpoint;
pub const DnsMutationArgs = routes.DnsMutationArgs;
pub const DomainEndpoint = routes.DomainEndpoint;
pub const DomainMutationEndpoint = routes.DomainMutationEndpoint;
pub const DomainMutationArgs = routes.DomainMutationArgs;
pub const HostingArgs = routes.HostingArgs;
pub const HostingEndpoint = routes.HostingEndpoint;
pub const HostingMutationEndpoint = routes.HostingMutationEndpoint;
pub const HostingMutationArgs = routes.HostingMutationArgs;
pub const EcommerceEndpoint = routes.EcommerceEndpoint;
pub const EcommerceMutationEndpoint = routes.EcommerceMutationEndpoint;
pub const HorizonsEndpoint = routes.HorizonsEndpoint;
pub const HorizonsMutationEndpoint = routes.HorizonsMutationEndpoint;
pub const ReachArgs = routes.ReachArgs;
pub const ReachEndpoint = routes.ReachEndpoint;
pub const ReachMutationEndpoint = routes.ReachMutationEndpoint;
pub const ReachMutationArgs = routes.ReachMutationArgs;

pub const virtualMachinesUrl = routes.virtualMachinesUrl;
pub const virtualMachineDetailsUrl = routes.virtualMachineDetailsUrl;
pub const endpointUrl = routes.endpointUrl;
pub const endpointPageUrl = routes.endpointPageUrl;
pub const actionDetailsUrl = routes.actionDetailsUrl;
pub const dockerEndpointUrl = routes.dockerEndpointUrl;
pub const dockerEndpointPath = routes.dockerEndpointPath;
pub const dockerMutationPath = routes.dockerMutationPath;
pub const dockerMutationPlanJson = routes.dockerMutationPlanJson;
pub const billingEndpointUrl = routes.billingEndpointUrl;
pub const billingMutationPath = routes.billingMutationPath;
pub const billingMutationPlanJson = routes.billingMutationPlanJson;
pub const dnsEndpointUrl = routes.dnsEndpointUrl;
pub const dnsEndpointPath = routes.dnsEndpointPath;
pub const dnsMutationPath = routes.dnsMutationPath;
pub const dnsMutationPlanJson = routes.dnsMutationPlanJson;
pub const domainEndpointUrl = routes.domainEndpointUrl;
pub const domainEndpointPath = routes.domainEndpointPath;
pub const domainMutationPath = routes.domainMutationPath;
pub const domainMutationPlanJson = routes.domainMutationPlanJson;
pub const hostingEndpointUrl = routes.hostingEndpointUrl;
pub const hostingEndpointPageUrl = routes.hostingEndpointPageUrl;
pub const hostingEndpointPath = routes.hostingEndpointPath;
pub const hostingMutationPath = routes.hostingMutationPath;
pub const hostingMutationPlanJson = routes.hostingMutationPlanJson;
pub const ecommerceEndpointUrl = routes.ecommerceEndpointUrl;
pub const ecommerceEndpointPageUrl = routes.ecommerceEndpointPageUrl;
pub const ecommerceMutationPath = routes.ecommerceMutationPath;
pub const ecommerceMutationPlanJson = routes.ecommerceMutationPlanJson;
pub const horizonsEndpointUrl = routes.horizonsEndpointUrl;
pub const horizonsEndpointPath = routes.horizonsEndpointPath;
pub const horizonsMutationPath = routes.horizonsMutationPath;
pub const horizonsMutationPlanJson = routes.horizonsMutationPlanJson;
pub const reachEndpointUrl = routes.reachEndpointUrl;
pub const reachEndpointPageUrl = routes.reachEndpointPageUrl;
pub const reachEndpointPath = routes.reachEndpointPath;
pub const reachMutationPath = routes.reachMutationPath;
pub const reachMutationPlanJson = routes.reachMutationPlanJson;
pub const vpsInventoryUrl = routes.vpsInventoryUrl;
pub const vpsInventoryPageUrl = routes.vpsInventoryPageUrl;
pub const vpsInventoryDetailUrl = routes.vpsInventoryDetailUrl;
pub const vpsInventoryDetailPath = routes.vpsInventoryDetailPath;
pub const vpsResourceMutationPath = routes.vpsResourceMutationPath;
pub const vpsResourceMutationPlanJson = routes.vpsResourceMutationPlanJson;
pub const firewallMutationPath = routes.firewallMutationPath;
pub const firewallMutationPlanJson = routes.firewallMutationPlanJson;
pub const pageUrl = routes.pageUrl;
pub const pathEscape = routes.pathEscape;
pub const appendQueryParam = routes.appendQueryParam;
pub const metricsUrl = routes.metricsUrl;
pub const metricsUrlAt = routes.metricsUrlAt;
pub const vpsMutationPath = routes.vpsMutationPath;
pub const vpsMutationPlanJson = routes.vpsMutationPlanJson;

pub const Client = struct {
    token: []const u8,
    base_url_override: []const u8 = base_url,

    pub fn init(token: []const u8) Client {
        return .{ .token = token };
    }

    pub fn getVirtualMachines(self: Client, io: Io, gpa: Allocator) !net_http.Response {
        const url = try virtualMachinesUrl(gpa, self.base_url_override);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getVirtualMachineDetails(self: Client, io: Io, gpa: Allocator, vm_id: []const u8) !net_http.Response {
        const url = try virtualMachineDetailsUrl(gpa, self.base_url_override, vm_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getVirtualMachineEndpoint(self: Client, io: Io, gpa: Allocator, vm_id: []const u8, endpoint: VmEndpoint) !net_http.Response {
        const url = try endpointUrl(gpa, self.base_url_override, vm_id, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getVirtualMachineEndpointPage(self: Client, io: Io, gpa: Allocator, vm_id: []const u8, endpoint: VmEndpoint, page: usize) !net_http.Response {
        const url = try endpointPageUrl(gpa, self.base_url_override, vm_id, endpoint, page);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getActionDetails(self: Client, io: Io, gpa: Allocator, vm_id: []const u8, action_id: []const u8) !net_http.Response {
        const url = try actionDetailsUrl(gpa, self.base_url_override, vm_id, action_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getDockerEndpoint(self: Client, io: Io, gpa: Allocator, vm_id: []const u8, endpoint: DockerEndpoint, project_name: ?[]const u8) !net_http.Response {
        const url = try dockerEndpointUrl(gpa, self.base_url_override, vm_id, endpoint, project_name);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getBillingEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: BillingEndpoint) !net_http.Response {
        const url = try billingEndpointUrl(gpa, self.base_url_override, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getDnsEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: DnsEndpoint, domain: []const u8, snapshot_id: ?[]const u8) !net_http.Response {
        const url = try dnsEndpointUrl(gpa, self.base_url_override, endpoint, domain, snapshot_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getDomainEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: DomainEndpoint, path_arg: ?[]const u8, tld: ?[]const u8) !net_http.Response {
        const url = try domainEndpointUrl(gpa, self.base_url_override, endpoint, path_arg, tld);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getHostingEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: HostingEndpoint, args: HostingArgs) !net_http.Response {
        const url = try hostingEndpointUrl(gpa, self.base_url_override, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getHostingEndpointPage(self: Client, io: Io, gpa: Allocator, endpoint: HostingEndpoint, args: HostingArgs, page: usize) !net_http.Response {
        const url = try hostingEndpointPageUrl(gpa, self.base_url_override, endpoint, args, page);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getEcommerceEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: EcommerceEndpoint) !net_http.Response {
        const url = try ecommerceEndpointUrl(gpa, self.base_url_override, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getEcommerceEndpointPage(self: Client, io: Io, gpa: Allocator, endpoint: EcommerceEndpoint, page: usize) !net_http.Response {
        const url = try ecommerceEndpointPageUrl(gpa, self.base_url_override, endpoint, page);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getHorizonsEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: HorizonsEndpoint, website_id: []const u8) !net_http.Response {
        const url = try horizonsEndpointUrl(gpa, self.base_url_override, endpoint, website_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getReachEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: ReachEndpoint, args: ReachArgs) !net_http.Response {
        const url = try reachEndpointUrl(gpa, self.base_url_override, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getReachEndpointPage(self: Client, io: Io, gpa: Allocator, endpoint: ReachEndpoint, args: ReachArgs, page: usize) !net_http.Response {
        const url = try reachEndpointPageUrl(gpa, self.base_url_override, endpoint, args, page);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getVpsInventoryEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: VpsInventoryEndpoint) !net_http.Response {
        const url = try vpsInventoryUrl(gpa, self.base_url_override, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getVpsInventoryEndpointPage(self: Client, io: Io, gpa: Allocator, endpoint: VpsInventoryEndpoint, page: usize) !net_http.Response {
        const url = try vpsInventoryPageUrl(gpa, self.base_url_override, endpoint, page);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getVpsInventoryDetail(self: Client, io: Io, gpa: Allocator, endpoint: VpsInventoryDetailEndpoint, id: []const u8) !net_http.Response {
        const url = try vpsInventoryDetailUrl(gpa, self.base_url_override, endpoint, id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn get(self: Client, io: Io, gpa: Allocator, url: []const u8) !net_http.Response {
        return try hostinger_transport.get(io, gpa, self.token, url);
    }

    pub fn getWithHeaders(self: Client, io: Io, gpa: Allocator, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
        return try hostinger_transport.getWithHeaders(io, gpa, self.token, url, route_headers);
    }

    /// Raw authenticated escape hatch for endpoints without a typed helper.
    pub fn requestJson(self: Client, io: Io, gpa: Allocator, method: std.http.Method, url: []const u8, body: ?[]const u8) !net_http.Response {
        return try hostinger_transport.requestJson(io, gpa, self.token, method, url, body);
    }
};
