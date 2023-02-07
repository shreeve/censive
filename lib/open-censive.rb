#!/usr/bin/env ruby

# require 'censive'
require './censive'

ARGV << "3.csv" if ARGV.empty?

path = ARGV.first
data = File.read(path)

csv = Censive.new(data, relax: true, excel: true)

data.size > 1e6 ? csv.parse : csv.parse.each {|cols| p cols }

csv.stats
