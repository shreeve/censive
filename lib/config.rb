config = {
  runs: 10,
  prelude: <<|,
    require "digest/md5"

    base = "/Users/shreeve/Data/Code/gems/censive/lib"

    require "csv"
    require File.join(base, "censive")

    name = file
    mode = file =~ /^ken/i ? "r:cp932" : "r"

    path = File.join(base, file)
    data = File.open(path, *mode) {|f| f.read }; nil
  benchmark: {
    csv: <<|,
      rows = CSV.parse(data)
    foo: <<|,
      x = 22
  },
}

#
#
#
#
# loop_count: 2
# prelude: |
#   require "digest/md5"
#
#   base = "/Users/shreeve/Data/Code/gems/censive/lib"
#
#   require "csv"
#   require File.join(base, "censive")
#
#   name = file
#   mode = file =~ /^ken/i ? "r:cp932" : "r"
#
#   path = File.join(base, file)
#   data = File.open(path, *mode) {|f| f.read }; nil
#
#   # $stderr.puts "\n\nFile: #{name.inspect}\nSize: #{File.stat(path).size} bytes\n\n"
# benchmark:
#   csv:     rows = CSV    .parse(data); #$stderr.puts "    csv => " + Digest::MD5.hexdigest(rows.join)
#   censive: rows = Censive.parse(data); #$stderr.puts "censive => " + Digest::MD5.hexdigest(rows.join)
# contexts:
#   - name: 3.csv
#     prelude: |
#       file = "3.csv"
#   - name: ken-10000.csv
#     prelude: |
#       file = "ken-10000.csv"
#   - name: data/geo-data.csv
#     prelude: |
#       file = "data/geo-data.csv"
