local test = require('./src/tests/zserge-gambiarra/gambiarra');
local ms = require('./src/moon_saga');

ms.moon_saga(
  function ()
    local task_id = coroutine.yield(
      ms.fork(
        function (t_id)
          print('exec', t_id);
        end
      )
    );

    print('forked', task_id);
  end
);