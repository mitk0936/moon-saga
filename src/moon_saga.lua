local iterate;
local moon_saga;

local logs_enabled = false;

local blocking_calls_initialized = false;
local action_waiters = { };
local waiting_iterators_to_complete = { };

-- Effects Declarations --

local put = function (action_id, payload)
  return {
    action_id = action_id or 'UNKNOWN',
    payload = payload,
    moon_effect = 'moon_saga.PUT'
  };
end

local take = function (action_id)
  return {
    action_id = action_id or 'UNKNOWN',
    moon_effect = 'moon_saga.TAKE'
  };
end

local take_every = function (action_id, iterator)
  return {
    action_id = action_id,
    iterator = iterator,
    moon_effect = 'moon_saga.TAKE_EVERY'
  };
end

local call = function (...)
  return {
    args = {...},
    moon_effect = 'moon_saga.CALL'
  };
end

local spawn = function (...)
  return {
    args = {...},
    moon_effect = 'moon_saga.SPAWN'
  };
end

local resolve = function (resolver, ...)
  return {
    args = {...},
    resolver = resolver,
    moon_effect = 'moon_saga.RESOLVE'
  };
end

local race = function (effects)
  return {
    racing_effects = effects,
    moon_effect = 'moon_saga.RACE'
  };
end

-- Running blocking calls logic

local flush_take_waiting_coroutines = function (action_id)
  if (action_waiters[action_id]) then
    local waiter_coroutines = { };

    for index, waiter in pairs(action_waiters[action_id]) do
      table.insert(waiter_coroutines, waiter.coroutine);
    end

    action_waiters[action_id] = { };
    collectgarbage();

    return waiter_coroutines;
  end
  
  return { };
end

local subscribe = function (action_id, moon_effect, coroutine)
  action_waiters[action_id] = action_waiters[action_id] or { };

  if (type(coroutine) ~= 'thread') then
    error('Subscription for an action waiter expects a coroutine.');
  end

  table.insert(action_waiters[action_id], {
    moon_effect = moon_effect,
    coroutine = coroutine
  });
end

local blocking_calls_waiter = function ()
  while (true) do
    local finished_iterator = coroutine.yield(
      take('MOON_SAGA.ITERATOR_FINISHED')
    );

    for index, blocking_call
    in pairs(
      waiting_iterators_to_complete
    ) do
      if (blocking_call.finished == false) then
        if (blocking_call.blocking_iterator == finished_iterator.iterator) then
          waiting_iterators_to_complete[index].finished = true;

          iterate(
            blocking_call.iterator,
            unpack(finished_iterator.results)
          );
        end
      end
    end

    finished_iterator.iterator = nil;
    collectgarbage();
  end
end

-- Running proccesses logic --

local proccess_index;
local get_next_proccess_index = function()
  proccess_index = proccess_index and proccess_index + 1 or 1;
  return proccess_index;
end

local running_processes = { };

local is_proccess_cancelled = function (iterator)
  for
    proccess_id,
    running_proccess
  in pairs(
    running_processes
  ) do
    local stopped = (
      iterator == running_proccess.coroutine and
      running_proccess.running == false
    );

    if (stopped) then
      return true, running_proccess;
    end
  end
end

-- Effects Implementation --

local DISPATCH = function (action_id, payload)
  if (action_id ~= 'MOON_SAGA.ITERATOR_FINISHED' and logs_enabled) then
    print('Dispatched: ', action_id);
  end

  for index, waiter
  in pairs(
    flush_take_waiting_coroutines(action_id)
  ) do
    iterate(waiter, payload);
  end
end

local TAKE = function (data, iterator)
  subscribe(
    data.action_id,
    'moon_saga.TAKE',
    iterator
  );
end

local SPAWN = function (data, proccess_id)
  local args = {unpack(data.args)};
  local forked_coroutine = coroutine.create(
    -- pops the first arguement, which is the coroutine function
    table.remove(args, 1)
  );

  running_processes[proccess_id] = {
    coroutine = forked_coroutine,
    args = args,
    running = true
  };

  iterate(forked_coroutine, proccess_id, unpack(args));
end

local TAKE_EVERY = function (data)
  moon_saga(function ()
    while (true) do
      local payload = coroutine.yield(
        take(data.action_id)
      );

      iterate(
        coroutine.create(data.iterator),
        payload
      );
    end
  end);
end

local CANCEL = function (proccess_id)
  if (running_processes[proccess_id]) then
    running_processes[proccess_id].running = false;
  end
end

local CALL = function (data, iterator)
  local args = {unpack(data.args)};
  args[1] = coroutine.create(args[1]);

  table.insert(waiting_iterators_to_complete, {
    iterator = iterator,
    blocking_iterator = args[1],
    finished = false
  });

  iterate(unpack(args));
end

local RESOLVE = function (data, iterator)
  if (type(data.resolver) ~= 'function') then
    error('Resolver must be a function');
  end

  data.resolver(
    function (...)
      iterate(iterator, true, ...);
      data.resolver = nil;
      collectgarbage();
    end, function (err)
      iterate(iterator, false, err);
      data.resolver = nil;
      collectgarbage();
    end,
    unpack(data.args)
  );
end

local RACE = function (data, iterator)
  local results = {};
  local race_id = get_next_proccess_index();
  local race_complete_action = 'moon_saga.RACE_COMPLETE.'..race_id;

  moon_saga(function ()
    local completed = coroutine.yield(
      take(race_complete_action)
    );

    results[completed.index] = completed.payload;

    iterate(iterator, results);
  end);

  moon_saga(function ()
    for index, effect
    in pairs(data.racing_effects)
    do
      local spawned_effect = spawn(function ()
        local result = { coroutine.yield(effect) };

        coroutine.yield(
          put(
            race_complete_action, {
              payload = result,
              index = index
            }
          )
        );
      end);

      coroutine.yield(spawned_effect);
    end
  end);
end

-- Handling of iteration process

local collect_coroutine_results = function (...)
  local results = {...};
  local resumed = table.remove(results, 1);

  return resumed, results;
end

iterate = function(iterator, ...)
  local cancelled, running_proccess = is_proccess_cancelled(iterator);

  if (cancelled) then
    running_proccess.coroutine = nil;
    collectgarbage();
    return;
  end

  local resumed, coroutine_results = collect_coroutine_results(
    coroutine.resume(iterator, ...)
  );
  
  if (not resumed) then
    error('Cannot resume coroutine...'..unpack(coroutine_results));
    return;
  end

  local yielded_helper = coroutine_results[1];
  local is_valid_helper_yielded = type(yielded_helper) == 'table' and yielded_helper.moon_effect ~= nil;

  if (is_valid_helper_yielded) then
    if (yielded_helper.moon_effect == 'moon_saga.PUT') then
      DISPATCH(yielded_helper.action_id, yielded_helper.payload);
    elseif (yielded_helper.moon_effect == 'moon_saga.TAKE') then
      return TAKE(yielded_helper, iterator);
    elseif (yielded_helper.moon_effect == 'moon_saga.TAKE_EVERY') then
      TAKE_EVERY(yielded_helper);
    elseif (yielded_helper.moon_effect == 'moon_saga.CALL') then
      return CALL(yielded_helper, iterator);
    elseif (yielded_helper.moon_effect == 'moon_saga.SPAWN') then
      local proccess_id = get_next_proccess_index();
      iterate(iterator, proccess_id);
      return SPAWN(yielded_helper, proccess_id);
    elseif (yielded_helper.moon_effect == 'moon_saga.RESOLVE') then
      return RESOLVE(yielded_helper, iterator);
    elseif (yielded_helper.moon_effect == 'moon_saga.RACE') then
      return RACE(yielded_helper, iterator);
    end
  end

  if (coroutine.status(iterator) ~= 'dead') then
    return iterate(iterator);
  else
    DISPATCH('MOON_SAGA.ITERATOR_FINISHED', {
      iterator = iterator,
      results = coroutine_results
    });
  end
end

moon_saga = function(...)
  for key, iterator in pairs({...}) do
    iterate(
      coroutine.create(iterator)
    );
  end
end

-- Initialize blocking calls waiter

if (not blocking_calls_initialized) then
  moon_saga(blocking_calls_waiter);
  blocking_calls_initialized = true;
end

return {
  set_logs = function (enabled)
    logs_enabled = enabled;
  end,
  put = put,
  dispatch = DISPATCH,
  take = take,
  take_every = take_every,
  call = call,
  spawn = spawn,
  cancel = CANCEL,
  resolve = resolve,
  race = race,
  moon_saga = moon_saga
};