{
  contexts: [
    {
      name: "Load MD5",
      begin: 'require "digest/md5"',
    },
  ],
  tasks: [
    {
      name: "csv",
      begin: <<~"|".strip,
        require "csv"

        path = ARGV[0] || "KEN_ALL.CSV"
        mode = path =~ /^ken/i ? "r:cp932" : "r"

        data = File.open(path, mode).read
      |
      loops: 20,
      script: <<~"|".strip,
        rows = CSV.parse(data)
        puts "%s %s (%d size)" % [Digest::MD5.hexdigest(rows.join), path, File.stat(path).size], ""
      |
    },
    {
      name: "censive",
      begin: <<~"|".strip,
        require "censive"

        path = ARGV[0] || "KEN_ALL.CSV"
        mode = path =~ /^ken/i ? "r:cp932" : "r"

        data = File.open(path, mode).read
      |
      loops: 20,
      script: <<~"|".strip,
        rows = Censive.parse(data)
        puts "%s %s (%d size)" % [Digest::MD5.hexdigest(rows.join), path, File.stat(path).size], ""
      |
    },
  ],
}
