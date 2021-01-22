#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ipaddr'
require 'net/ip'
require 'optparse'
require 'socket'
require 'yaml'

DEFAULT_CONF_PATHS = [
  './ddsnet4u.yaml',
  "#{ENV['HOME']}/ddsnet4u.yaml",
  '/usr/local/etc/ddsnet4u.yaml',
  '/etc/ddsnet4u/ddsnet4u.yaml'
].freeze

options = { conf_paths: DEFAULT_CONF_PATHS }
option_parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ddsnet4u.rb [options]'
  opts.separator ''
  opts.separator 'Specifc options:'

  opts.on('-c', '--config PATH', String) do |c|
    options[:conf_paths] = [c]
  end

  opts.on('-n', '--[no-]noop', 'Do not change routing table') do |n|
    options[:noop] = [n]
  end

  opts.on_tail('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end
option_parser.parse!

def get_interface_ips(name:)
  # returns all address, including ipv6
  ifaddrs = Socket.getifaddrs.find_all { |x| x.name == name }
  # return only ipv4 addresses
  ifaddrs.filter { |x| x.addr.ipv4? }
end

# Socket deals in Socket::Ifaddr objects, which can't be compared to see if
# they are within a given subnet, so we want to convert them into IPAddr
# objects.
def ifaddr_to_ipaddr(addrs:)
  ips = addrs.filter do |x|
    ip = x.addr.ip_address
    # Oddly, #netmask returns an Addrinfo object with the mask as the ip address
    mask = x.netmask.ip_address
    return nil if ip.nil? || mask.nil?

    true
  end

  # ignore netmask as we want to treat this IP as a /32
  # ips.collect { |x| IPAddr.new("#{x.addr.ip_address}/#{x.netmask.ip_address}") }
  ips.collect { |x| IPAddr.new("#{x.addr.ip_address}/32") }
end

def ipaddr_to_prefix(ipaddr:)
  "#{ipaddr}/#{ipaddr.prefix}"
end

def stringify_ipaddr(ipaddr:)
  "#{ipaddr}/#{ipaddr.prefix}"
end

# find a readable conf file
conf_file = options[:conf_paths].find { |x| File.exist?(x) and File.readable?(x) }
raise("unable to find a conf file at these path(s): #{options[:conf_paths]}") if conf_file.nil?

conf = YAML.safe_load(File.read(conf_file))

IFACE_NAME = conf['interface']
raise('"interface" key missing from conf file') if IFACE_NAME.nil?

DDS_SUBNETS = conf['subnets']
raise('"subnets" key missing from conf file') if DDS_SUBNETS.nil?

# convert hash of prefix strings into array of hash w/ IPAddr objects
# - input is a hash to prevent duplicates
# - use an array so that we can sort it later on
subnets = DDS_SUBNETS.each_with_object([]) { |x, n| n << { IPAddr.new(x.first) => x.last } }

puts "looking for IPs assigned to interface: #{IFACE_NAME}"
iface_ips = get_interface_ips(name: IFACE_NAME)
raise("interface #{IFACE_NAME} does not exist or has no IPv4 addresses assigned") if iface_ips.empty?

ip = ifaddr_to_ipaddr(addrs: iface_ips).first
puts "assuming IP is: #{ip}"

# find all subnets which contain our ip
matching_subs = subnets.filter { |x| x.keys.first.include?(ip) }

# exit 0 if there are no matching subnets as this might be a k8s cluster on
# which nothing is needed
if matching_subs.empty?
  puts 'no matching subnets found, nothing to do, exiting...'
  exit 0
end

# find the most specific prefix
mysub = matching_subs.sort_by { |x| x.keys.first.prefix }.reverse.first
puts "assuming subnet is: #{stringify_ipaddr(ipaddr: mysub.keys.first)}"

# figure out gw
mygw = mysub.values.first['gw']
puts "assuming DDS gateway is: #{mygw}"

# figure out subnets which should have routes
# remove the interface's subnet from the list of all subnets and routes will be
# needed for what remains -- this will work only if there are not other
# interfaces/ips in these subnets
required_subnets = subnets.reject { |x| x.keys.first == mysub.keys.first }

required_routes = required_subnets.collect do |x|
  Net::IP::Route.new(
    prefix: ipaddr_to_prefix(ipaddr: x.keys.first),
    dev: IFACE_NAME,
    via: mygw
  )
end
puts 'routes for these subnets is required:'
required_subnets.each { |x| puts " - #{stringify_ipaddr(ipaddr: x.keys.first)}" }

# figure out existing subnet routes
current_routes = Net::IP.routes
puts 'routes already exist for:'
current_routes.each { |x| puts " - #{x.prefix}" }

# look for needed but missing routes by prefix -- this is neglicting possible
# routes via other interfaces but if routes exist via other interfaces we are
# already in trouble...
inject_routes = required_routes.reject do |x|
  current_routes.any? { |i| i.prefix == x.prefix }
end
puts 'need to inject routes for:'
inject_routes.each { |x| puts " - #{x.prefix}" }

exit 0 if options[:noop]

# inject routes
route_errors = 0
inject_routes.each do |x|
  begin
    current_routes.add(x)
  rescue StandardError => e
    route_errors += 1
    puts "failed to inject route for #{x.prefix}"
    puts e
  end
end

exit 1 if route_errors
