#!/usr/bin/env ruby

require "csv"
require "digest/md5"

path = ARGV[0] || "KEN_ALL.CSV"
mode = path =~ /^ken/i ? "r:cp932:us-ascii" : "r"

data = File.open(path, mode).read
rows = CSV.parse(data)

puts "%s %s (%d size)" % [Digest::MD5.hexdigest(rows.join), path, File.stat(path).size], ""
