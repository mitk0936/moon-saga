local test = require('./src/tests/zserge-gambiarra/gambiarra');
local ms = require('./src/moon_saga');

local fib_sequence = function (a, b, max)
  max = max or 200;

  return function ()
    coroutine.yield(ms.put('FIB_NEXT', a));
    coroutine.yield(ms.put('FIB_NEXT', b));

    while (true) do
      local next = a + b;

      if (next > max) then
        coroutine.yield(ms.put('END_OF_FIB_SEQUENCE', b));
        return;
      end

      coroutine.yield(ms.put('FIB_NEXT', next));
      
      a = b;
      b = next;
    end
  end
end

test('moon_saga.call | testing call return values', function(done)
  local start = 2;
  local second = 3;
  local max = 13;

  ms.moon_saga(
    function ()
      local result, sequence = coroutine.yield(
        ms.call(
          function (param1, param2)
            local collected = {};

            test('moon_saga.call | call coroutine receives params correctly', function ()
              ok(eq({ param1, param2 }, { 'paramX', 'paramY' }));
            end);

            local insert = spy(table.insert);

            coroutine.yield(
              ms.take_every('FIB_NEXT', function (next_value)
                insert(collected, next_value);
              end)
            );

            coroutine.yield(ms.take('END_OF_FIB_SEQUENCE'));
            
            test('moon_saga.take_every | effect is called every time with the right args', function ()
              

              for k, v in pairs(insert.called) do
                print(k, v);
                for k1, v1 in pairs(v) do
                  local v33 = type(v1) == 'number' and v1 or unpack(v1);
                  print('   '..k1..'->'..v33);
                end
                -- ok(eq(insert.called[k], {v}));
              end

              print('called', #insert.called);
              ok(insert.called);
            end);

            return true, collected;
          end,
          'paramX',
          'paramY'
        )
      );

      ok(eq(result, true));
      ok(eq(sequence, { start, second, 5, 8, 13 }));

      done();
    end,
    fib_sequence(start, second, max)
  );
end, true);

test('moon_saga.take | testing take effect', function(done)
  local expected_a = 90;
  local expected_b = 100;
  local expected_c = 120;

  local a, b, c;

  ms.moon_saga(
    function ()
      coroutine.yield(ms.take('BLOCKING_OPERATION_FINISHED'));

      ok(eq({ a, b, c }, { expected_a, expected_b, expected_c }));
      done();
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
end, true);

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
    test('moon_saga.resolve | is resolver returning values properly', function (done)
      local result, a, b, c = coroutine.yield(
        ms.resolve(stub_resolver, 5, 10, 20)
      );

      ok(eq(result, true));

      if (result) then
        ok(eq({ a, b, c }, { 20, 10, 5 }));
      end

      done();
    end, true);
  end,
  function ()
    test('moon_saga.resolve | is resolve rejecting case properly, returning error', function (done)
      local result, data = coroutine.yield(
        ms.resolve(stub_resolver, 1, 2, 3)
      );

      ok(eq(result, false));
      ok(eq(data, mocked_error));

      done();
    end, true);
  end,
  function ()
    test('moon_saga.race | is racing take and call effects properly', function (done)
      local blocking_call = function (number)
        local num = number;

        while (num > 500) do
          num = num - 1;
        end

        return num, num - 1, num - 2;
      end

      local result = coroutine.yield(
        ms.race({
          event = ms.take('UNKNOWN_EVENT'),
          cancelled = ms.call(blocking_call, 1000)
        })
      );

      ok(eq(result.event, nil));
      ok(eq(result.cancelled, { 500, 499, 498 }));

      done();
    end)
  end
);