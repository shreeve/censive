# censive

A quick and lightweight CSV handling library for Ruby

## Example

```ruby
#!/usr/bin/env ruby

STDOUT.sync = true

require 'censive'
require 'fileutils'

abort "usage: #{File.basename($0)} <files>" if ARGV.empty?

rand = `LC_ALL=C tr -dc a-zA-Z0-9 < /dev/random | head -c12`

rows = []
cols = []
coun = 0
full = 0

ARGV.each do |path|
  File.file?(path) or next

  print "Processing #{path.inspect}"

  rows.clear
  cols.clear
  seen = 0
  coun += 1

  dest = "#{path}-#{rand}"

  begin
    Censive.writer(dest) do |file|
      Censive.reader(path, excel: true, relax: true).each do |cols|
        file << cols
        seen += 1
        print "." if (seen % 1e5) == 0 # give a status update every so often
      end
    end
    FileUtils.mv(dest, path)
    full += (seen - 1)
    puts " (#{seen - 1} rows of data)"
  rescue
    puts " - unable to process (#{$!})"
    FileUtils.rm_f(dest)
  end
end

puts "Processed #{coun} files with a total of #{full} rows of data" if coun > 1
```

## Convert a CSV file to a TSV file

```ruby
require 'censive'

# read in a comma-separated csv file
data = File.read('data.csv')

# write out a tab-separated tsv file
Censive.writer('out.tsv', sep: "\t", mode: :full) do |out|
  Censive.new(data, excel: true, relax: true).each do |row|
    out << row
  end
end
```

Or, you can be more succinct with:

```ruby
require 'censive'

csv = Censive.new(DATA.read, excel: true, relax: true, strip: true)
csv.export(sep: "|", excel: true) # pipe separated, protect leading zeroes

__END__
Name,Age, Shoe
  Alice,  27,5
Bob,  33,10 1/2
  Charlie or "Chuck",=B2 + B3,9
"Doug E Fresh",="007",001122
Subtotal,=sum(B2:B5),="01234"
```

Which returns:

```
Name|Age|Shoe
Alice|27|5
Bob|33|10 1/2
"Charlie or ""Chuck"""|=B2 + B3|9
Doug E Fresh|="007"|="001122"
Subtotal|=sum(B2:B5)|="01234"
```
