#!/usr/bin/env ruby

require 'csv'

ARGV << "3.csv" if ARGV.empty?

@rows = []
@cells = 0
CSV.foreach(ARGV.shift, liberal_parsing: true) do |row|
  row.each {|cell| cell && cell.size >= 3 && cell.sub!(/\A="/, '') && cell.sub!(/"\z/, '') }
  @rows << row
  @cells += row.size
end

p [:rows, @rows.size]
p [:cells, @cells]
