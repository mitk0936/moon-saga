local lu = require('./src/tests/lib/luaunit');
local ms = require('./src/moon_saga');

ms.set_logs(true);

require('./src/tests/blocking_calls_spec');

os.exit( lu.LuaUnit.run() );