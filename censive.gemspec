Gem::Specification.new do |s|
  s.name        = "censive"
  s.version     = `grep -m 1 '^\s*VERSION' lib/censive.rb | head -1 | cut -f 2 -d '"'`
  s.author      = "Steve Shreeve"
  s.email       = "steve.shreeve@gmail.com"
  s.summary     =
  s.description = "A quick and lightweight CSV handling library for Ruby"
  s.homepage    = "https://github.com/shreeve/censive"
  s.license     = "MIT"
  s.files       = `git ls-files`.split("\n") - %w[.gitignore]
  s.executables = `(cd bin 2>&1) > /dev/null && git ls-files .`.split("\n")
end
