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

return {
  fib_sequence = fib_sequence
};