#!/usr/bin/env ruby

require "csv"
require "digest/md5"

data = File.open("KEN_ALL.CSV", "r:cp932").read

rows = CSV.parse(data)

puts Digest::MD5.hexdigest(rows.join)
