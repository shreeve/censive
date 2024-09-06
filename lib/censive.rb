#!/usr/bin/env ruby

# ============================================================================
# censive - A quick and lightweight CSV handling library for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: June 28, 2023
#
# https://crystal-lang.org/api/1.7.2/CSV.html (Crystal's CSV library)
# https://github.com/ruby/strscan/blob/master/ext/strscan/strscan.c
#
# Thanks to Sutou Kouhei (kou) for his excellent advice on using scan better
# ============================================================================
# HIGHLIGHTS:
# 1. Faster than Ruby's default CSV library
# 2. Lightweight code with streamlined and optimized logic
# 3. Support most non-compliant CSV variations (@excel, @relax, etc)
# 4. Support most commonly used CSV options (@sep, @quote, @strip, @drop, etc)
#
# TODO:
# 1. Support IO streaming
# 2. Review all encodings, we may be losing speed when mixing encodings
# 3. Speedup possible if our @unquoted regex reads beyond @eol's
# 4. Will using String#freeze give us a speed up?
# 5. Implement support for scan_until(string) <= right now only regex is valid
# ============================================================================

require "stringio"
require "strscan"

class Censive < StringScanner
  VERSION="1.1.1"

  attr :encoding, :out, :rows

  def self.read(...)
    new(...).read
  end

  def self.write(obj=nil, **opts, &code)
    case obj
    when String
      if block_given?
        File.open(obj, "w") {|io| new(out: io, **opts, &code) }
      else
        new(out: File.open(obj, "w"), **opts)
      end
    when StringIO, IO, nil
      new(out: obj, **opts, &code)
    else
      abort "#{File.basename($0)}: #{self}.write can't use #{obj.class} objects"
    end
  end

  def initialize(str=nil,
    drop:     false   , # drop trailing empty columns?
    encoding: nil     , # character encoding
    excel:    false   , # literals ="01" formulas =A1 + B2 http://bit.ly/3Y7jIvc
    mode:     :compact, # output mode: compact or full
    out:      nil     , # output stream, needs to respond to <<
    quote:    '"'     , # quote character
    relax:    false   , # relax quote parsing so ,"Fo"o, => ,"Fo""o",
    rowsep:   "\n"    , # row separator for output
    sep:      ","     , # column separator character
    strip:    false   , # strip columns when reading
    **opts              # grab bag
  )
    # initialize data source
    if str && str.size < 100 && File.readable?(str)
      str = File.open(str, encoding ? "r:#{encoding}" : "r").read
    else
      str ||= ""
      str = str.encode(encoding) if encoding
    end
    super(str)
    reset

    # config options
    @cheat    = true
    @drop     = drop
    @encoding = str.encoding
    @excel    = excel
    @mode     = mode
    @out      = out || $stdout
    @relax    = relax
    @strip    = strip

    # config strings
    @quote    = quote
    @rowsep   = rowsep
    @sep      = sep

    # static strings
    @cr       = "\r"
    @lf       = "\n"
    @es       = ""
    @eq       = "="

    # combinations
    @esc      = (@quote * 2)
    @seq      = [@sep, @eq].join # used for parsing in excel mode

    # regexes
    xsep      = Regexp.escape(@sep) # may need to be escaped
    @eoc      = /(?=#{"\\" + xsep}|#{@cr}|#{@lf}|\z)/ # end of cell
    @eol      = /#{@cr}#{@lf}?|#{@lf}/                # end of line
    @escapes  = /(#{"\\" + @quote})|#{xsep}|#{@cr}|#{@lf}/
    @quotable = /#{xsep}|#{@cr}|#{@lf}/
    @quotes   = /#{"\\" + @quote}/
    @seps     = /#{"\\" + xsep}+/
    @quoted   = @excel ? /(?:=)?#{"\\" + @quote}/ : @quote
    @unquoted = /[^#{"\\" + xsep}#{@cr}#{@lf}][^#{"\\" + @quote}#{@cr}#{@lf}]*/
    @leadzero = /\A0\d*\z/

    yield self if block_given?
  end

  def reset(str=nil)
    @rows = nil
    @cols = @cells = 0

    self.string = str if str
    @encoding = string.encoding
    super()
  end

  # ==[ Reader ]==

  def read
    @rows = []
    while row = next_row
      @rows << row
      count = row.size
      @cols = count if count > @cols
      @cells += count
    end
    self
  end

  def next_row
    if @cheat and line = scan_until(@eol)
      row = line.chomp!.split(@sep, -1)
      row.each do |col|
        next if (saw = col.count(@quote)).zero?
        next if (saw == 2) && col.delete_prefix!(@quote) && col.delete_suffix!(@quote)
        @cheat = false
        break
      end if line.include?(@quote)
      @cheat and return @strip ? row.each(&:strip!) : row
      unscan
    end

    token = next_token or return
    row = []
    row.push(*token)
    row.push(*token) while token = next_token
    row
  end

  def next_token
    if scan(@quoted) # quoted cell
      token = ""
      while true
        token << (scan_until(@quotes) or bomb "unclosed quote")[0..-2]
        token << @quote and next if scan(@quote)
        scan(@eoc) and break
        @relax or bomb "invalid character after quote"
        token << @quote + (scan_until(@quotes) or bomb "bad inline quote")
        scan(@eoc) and break
      end
      scan(@sep)
      @strip ? token.strip : token
    elsif match = scan(@unquoted) # unquoted cell(s)
      if check(@quote) && !match.chomp!(@sep) # if we see a stray quote
        unless @excel && match.chomp!(@seq) # unless an excel literal, fix it
          match << (scan_until(@eoc) or bomb "stray quote")
          scan(@sep)
        end
      end
      tokens = match.split(@sep, -1)
      @strip ? tokens.map!(&:strip) : tokens
    elsif scan(@sep)
      match = scan(@seps)
      match ? match.split(@sep, -1) : @es
    else
      scan(@eol)
      nil
    end
  end

  def each
    @rows or read
    @rows.each {|row| yield row }
  end

  # ==[ Writer ]==

  def write(*args, **opts, &code)
    if args.empty? && opts.empty?
      block_given? ? each(&code) : each {|row| @out << row }
    elsif block_given?
      Censive.write(*args, **opts, &code)
    else
      Censive.write(*args, **opts) {|csv| each {|row| csv << row }}
    end
  end

  # output a row
  def <<(row)

    # drop trailing empty columns
    row.pop while row.last.empty? if @drop

    s,q = @sep, @quote
    out = case @mode
    when :compact
      case @excel ? 2 : quote_type(row.join)
      when 0
        row
      when 1
        row.map do |col|
          col&.match?(@quotable) ? "#{q}#{col}#{q}" : col
        end
      else
        row.map do |col|
          @excel && col =~ @leadzero ? "=#{q}#{col}#{q}" :
          case quote_type(col)
          when 0 then col
          when 1 then "#{q}#{col}#{q}"
          else        "#{q}#{col.gsub(q, @esc)}#{q}"
          end
        end
      end
    when :full
      if @excel
        row.map do |col|
          col =~ @leadzero ? "=#{q}#{col}#{q}" : "#{q}#{col.gsub(q, @esc)}#{q}"
        end
      else
        row.map {|col| "#{q}#{col.gsub(q, @esc)}#{q}" }
      end
    end.join(s)

    @out << out + @rowsep
  end

  # ==[ Helpers ]==

  def bomb(msg)
    abort "\n#{File.basename($0)}: #{msg} at character #{pos} near '#{string[pos-4,7]}'"
  end

  # returns 2 (must be quoted and escaped), 1 (must be quoted), 0 (neither)
  def quote_type(str)
    if idx = str&.index(@escapes)
      $1 ? 2 : str.index(@quote, idx) ? 2 : 1
    else
      0
    end
  end

  def stats
    wide = string.size.to_s.size
    puts "%#{wide}d rows"    % @rows.size
    puts "%#{wide}d columns" % @cols
    puts "%#{wide}d cells"   % @cells
    puts "%#{wide}d bytes"   % string.size
  end

end

if __FILE__ == $0
  str = DATA.gets("\n\n").chomp
  # str = File.read(ARGV.first || "lc-2023.csv")
  # str = File.open("KEN_ALL.CSV", "r:cp932").read

  # require "stringio"
  # csv = Censive.new(str, excel: true, relax: true)
  # out = "" # StringIO.new
  # csv.export(out: out) # (excel: true) # sep: "|")
  # puts out # .string

  # csv = Censive.new(str, excel: true, relax: true, out: "")
  # out = csv.export
  # puts out.out

  puts Censive.read(str, excel: true, relax: true).write
end

__END__
"AAA "BBB",CCC,"DDD"

"CHUI, LOK HANG "BENNY",224325325610,="001453","Hemoglobin A1c",=""
"Don",="007",10,"Ed"
Name,Age,,,Shoe,,,
"Alice",27,5
Bob,33,10 1/2
Charlie or "Chuck",=B2 + B3,9
Subtotal,=sum(B2:B5),="01234"
A,B,C,D
A,B,"C",D
A,B,C",D
A,B,"C",D
08/27/2022,="73859443",="04043260",,"Crossover @ Mathilda","CHO, JOELLE "JOJO"",08/19/2022
123,
123,"CHO, JOELLE "JOJO"",456
123,"CHO, JOELLE ""JOJO""",456
=,=x,x=,="x",="","","=",123,0123,="123",="0123"
,=x,x=,x,,,,,,=,,123,="0123",123,,="0123"
