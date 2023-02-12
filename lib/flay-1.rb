{
  environments: [
    {
      name: "Environment 1",
      begin: <<~"|".strip,
        ruby_ver = "3.2.0" # environment 1 begin
      |
      end: <<~"|".strip,
        # environment 1 end
      |
    },
    {
      name: "Environment 2",
      begin: <<~"|".strip,
        # environment 2 begin
      |
      end: <<~"|".strip,
        # environment 2 end
      |
    },
  ],

  contexts: [
    {
      name: "Context 1",
      begin: <<~"|".strip,
        require "csv" # context 1 begin
      |
      end: <<~"|".strip,
        # context 1 end
      |
    },
    {
      name: "Context 2",
      begin: <<~"|".strip,
        require "censive" # context 2 begin
      |
      end: <<~"|".strip,
        # context 2 end
      |
    },
  ],

  tasks: [
    {
      name: "Task 1",
      runs: 35,
      begin: <<~"|".strip,
        # task 1 begin
      |
      script: <<~"|",

        # <<<<<
        # task 1 script
        a = [*1..1e5]
        a.sum
        # >>>>>
      |
      end: <<~"|".strip,
        # task 1 end
      |
    },
    {
      name: "Task 2",
      secs: 30,
      begin: <<~"|".strip,
        # task 2 begin
      |
      script: <<~"|".strip,
        a = 0
        1e5.to_i.times {|n| a += n }
        a
      |
      end: <<~"|".strip,
        # task 2 end
      |
    },
  ],
}
