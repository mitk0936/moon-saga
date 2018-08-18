local lu = require('./src/tests/lib/luaunit');
local helpers = require('./src/tests/helpers');
local ms = require('./src/moon_saga');

-- Testing lib helpers
  
function testingMoonSagaBlockingOperation()
  local start = 2;
  local second = 3;
  local max = 13;

  ms.moon_saga(
    function ()
      local ok, sequence = coroutine.yield(
        ms.call(
          function (param1, param2)
            local collected = {};

            lu.assertEquals(param1, 'paramX');
            lu.assertEquals(param2, 'paramY');

            coroutine.yield(
              ms.take_every('FIB_NEXT', function (nextValue)
                table.insert(collected, nextValue);
              end)
            );

            coroutine.yield(ms.take('END_OF_FIB_SEQUENCE'));
            return true, collected;
          end,
          'paramX',
          'paramY'
        )
      );

      lu.assertEquals(ok, true);
      lu.assertEquals(sequence, { start, second, 5, 8, 13 });

      print('EXECUTED');
    end,
    helpers.fib_sequence(start, second, max)
  );
end

function testingCallMultipleResults()
  local expected_a = 90;
  local expected_b = 100;
  local expected_c = 120;

  local a, b, c;

  ms.moon_saga(
    function ()
      coroutine.yield(ms.take('BLOCKING_OPERATION_FINISHED'));

      lu.assertEquals(a, expected_a);
      lu.assertEquals(b, expected_b);
      lu.assertEquals(c, expected_c);
      
      print('EXECUTED');
    end,
    function ()
      a, b, c = coroutine.yield(
        ms.call(
          function ()
            local number = 0;
        
            while (number ~= expected_a) do
              number = number + 1;
            end

            return number, expected_b, expected_c;
          end
        )
      );

      coroutine.yield(ms.put('BLOCKING_OPERATION_FINISHED'));
    end
  );
end

function testingResolvers()
  local mocked_error = 'Numbers sum is under 30';

  local stub_resolver = function (resolve, reject, a, b, c)
    if (a + b + c > 30) then
      resolve(c, b, a);
    else
      reject(mocked_error);
    end
  end

  ms.moon_saga(
    function ()
      local ok, a, b, c = coroutine.yield(
        ms.resolve(stub_resolver, 5, 10, 20)
      );

      lu.assertEquals(ok, true);

      if (ok) then
        lu.assertEquals({ a, b, c }, { 20, 10, 5 });
        print('EXECUTED');
      end
    end,
    function ()
      local ok, result = coroutine.yield(
        ms.resolve(stub_resolver, 1, 2, 3)
      );

      lu.assertEquals(ok, false);
      lu.assertEquals(result, mocked_error);
      print('EXECUTED');
    end
  );
end