local test = require('./src/tests/zserge-gambiarra/gambiarra');
local ms = require('./src/moon_saga');

ms.moon_saga(
  function ()
    local number = 0;
    local expected_changed_number = 42;

    local task_id = coroutine.yield(
      ms.spawn(
        function ()
          coroutine.yield(
            ms.take('SPAWNED_FUNC_COMPLETED')
          );

          number = expected_changed_number;

          coroutine.yield(
            ms.put('RESULT_UPDATED')
          );
        end
      )
    );

    coroutine.yield(
      ms.spawn(
        function (p_id, arg1, arg2, arg3)
          number = 1;

          test('moon_saga.spawn | spawned coroutine receives params correctly', function ()
            ok(eq({ arg1, arg2, arg3 }, { 'arg1', 'arg2', 'arg3' }));
          end);

          ms.dispatch('SPAWNED_FUNC_COMPLETED');
        end,
        'arg1',
        'arg2',
        'arg3'
      )
    );

    test('moon_saga.spawn | spawned function started after main routine is resumed', function ()
      ok(eq(number, 0));
    end);

    test('moon_saga.spawn | result updated after spawned function finished', function (done)
      ms.moon_saga(function ()
        coroutine.yield(
          ms.take('RESULT_UPDATED')
        );
        
        ok(eq(number, 33));
        done();
      end)
    end, true);
  end
);