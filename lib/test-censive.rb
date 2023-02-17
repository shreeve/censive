#!/usr/bin/env ruby

require "./censive"
require "digest/md5"

path = ARGV[0] || "data/KEN_ALL.CSV"
mode = path =~ /(^|\/)ken/i ? "r:cp932" : "r"

data = File.open(path, mode).read
rows = Censive.parse(data)

puts "%s %s (%d size)" % [Digest::MD5.hexdigest(rows.join), path, File.stat(path).size], ""
