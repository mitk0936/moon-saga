local ms = require('./src/moon_saga');
local test = require('./src/tests/zserge-gambiarra/gambiarra');

-- ms.set_logs(true);

-- local passed = 0
-- local failed = 0
-- local clock = 0

-- 
-- test(function(event, testfunc, msg)
--     if event == 'begin' then
--         print('Started test', testfunc)
--         passed = 0
--         failed = 0
--         clock = os.clock()
--     elseif event == 'end' then
--         print('Finished test', testfunc, passed, failed, os.clock() - clock)
--     elseif event == 'pass' then
--         passed = passed + 1
--     elseif event == 'fail' then
--         print('FAIL', testfunc, msg)
--         failed = failed + 1
--     elseif event == 'except' then
--         print('ERROR', testfunc, msg)
--     end
-- end)

require('./src/tests/blocking-calls-spec');
require('./src/tests/non-blocking-calls-spec');