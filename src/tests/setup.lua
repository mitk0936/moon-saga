local test = require('./src/tests/zserge-gambiarra/gambiarra');
local reporter = require('./src/tests/reporter');

local tests_output = reporter(test);

require('./src/tests/all');

tests_output();