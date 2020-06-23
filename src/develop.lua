local ms = require('./src/moon_saga_refactored');
local saga = ms.create();

local some_blocking_function = function (...)
  print(...);
  local numbers = {...};
  return numbers[1] + numbers[2];
end

saga.run(
  function ()
    local result = coroutine.yield(
      saga.take('WHATEVER_MY_ACTION_IS')
    );

    print('Result is', result.ok);

    return 22, 33, 33;
  end,
  function ()
    coroutine.yield(
      saga.put('WHATEVER_MY_ACTION_IS', { ok = true })
    );
  end,
  function ()
    local my_result = coroutine.yield(
      saga.call(some_blocking_function, 1, 2, 3)
    );

    print('MY_RESULT', my_result);
  end,
  function ()

    print('will be blocked');

    coroutine.yield(
      saga.call(function ()
        local forked_id = coroutine.yield(
          saga.fork(function (my_id, ...)
            -- body

            print('my id is', my_id);
            print(...);

            coroutine.yield(
              saga.spawn(function()
                coroutine.yield(saga.take('ASASD'));
                print('Spawn Continued');
              end)
            );
          end, 9 , 8, 7)
        );

        print('Continue');
      end)
    );

    print('NOW???');

    coroutine.yield(saga.put('ASASD'));
  end,
  function ()
    local process_id = coroutine.yield(
      saga.fork(function ()
        coroutine.yield(
          saga.spawn(function ()
            coroutine.yield(
              saga.take('AFTER_CANCEL')
            );

            print('Spawn works');
          end)
        );

        local process = coroutine.yield(
          saga.fork(function ()
            while (true) do
              coroutine.yield(
                saga.take('PING')
              );

              coroutine.yield(
                saga.put('PONG')
              );
            end
          end)
        );

        print(process);
      end)
    );

    coroutine.yield(
      saga.fork(function ()
        coroutine.yield(
          saga.take('PONG')
        );

        coroutine.yield(
          saga.cancel(process_id)
        );

        coroutine.yield(
          saga.put('AFTER_CANCEL')
        );

        coroutine.yield(
          saga.put('PING')
        );
      end)
    );

    print('first ping');

    coroutine.yield(
      saga.put('PING')
    );
  end
);