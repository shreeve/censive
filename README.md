# censive

A quick and lightweight CVS handling library for Ruby

## Writing CSV

```ruby
require 'censive'

# read in a comma-separated csv file
data = File.read('data.csv')

# write out a tab-separated tsv file
Censive.writer('out.tsv', sep: "\t", mode: :full) do |out|
  Censive.new(data).each do |row|
    out << row
  end
end
```
