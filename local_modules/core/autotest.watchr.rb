require 'json'

def run_all_tests
  run_test("All", (Dir['test/**/*.coffee']+Dir['test/*.coffee'])*" ")
end

def run(tests)
  result = `mocha -b -t 5000 --colors --compilers coffee:coffee-script/register --reporter spec #{tests} 2>&1`
  result = result.sub("\t","")
  puts result
end

def run_single_test(name, test)
  if File.exist? test then
    run_test name, test
  end
end

def run_test(name, test)
  puts "Running Test(s) [#{test}] at #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
  result_text = run(test)
end

run_all_tests
puts "Autotest Started"
watch("test/(.*_tests)+.coffee") { |m| run_test(m[1], m[0]) }
watch("test/(.*/.*_tests)+.coffee") { |m| run_test(m[1], m[0]) }
watch("test/(.*)/.*_helpers+.coffee") { |m| run_test(m[1], Dir["test/#{m[1]}/*.coffee"]*" ") }
watch("src/(.*).coffee") { |m| run_single_test(m[1], "test/#{m[1]}_tests.coffee") }
watch("src/(.*/.*).coffee") { |m| run_single_test(m[1], "test/#{m[1]}_tests.coffee") }