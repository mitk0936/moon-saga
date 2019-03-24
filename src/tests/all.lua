local ms = require('./src/moon_saga');

-- ms.set_logs(true);

require('./src/tests/blocking-calls-spec');
require('./src/tests/non-blocking-calls-spec');