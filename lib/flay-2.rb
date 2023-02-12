{
  environments: [
    {
      name: "Load MD5",
      begin: 'require "digest/md5"',
    },
  ],

  contexts: [
    {
      name: "csv",
      begin: <<~"|",
        require "csv"

        path = ARGV[0] || "KEN_ALL.CSV"
        mode = path =~ /^ken/i ? "r:cp932" : "r"

        data = File.open(path, mode).read
        rows = CSV.parse(data)
      |
    },
    {
      name: "censive",
      begin: <<~"|",
        require "censive"

        path = ARGV[0] || "KEN_ALL.CSV"
        mode = path =~ /^ken/i ? "r:cp932" : "r"

        data = File.open(path, mode).read
        rows = Censive.parse(data)
      |
    },
  ],

  tasks: [
    {
      name: "Benchmark",
      loops: 3,
      script: <<~"|",
        puts "%s %s (%d size)" % [Digest::MD5.hexdigest(rows.join), path, File.stat(path).size], ""
      |
    },
  ],
}
