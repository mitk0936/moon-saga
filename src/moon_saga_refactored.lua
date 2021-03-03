local moduleName = ...
local M = {}
_G[moduleName] = M;

-- TODO: race, takeLatest, takeEvery, all, channels, resolvers

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

local call = function (func, ...)
  return {
    func = func,
    args = {...},
    moon_effect = 'moon_saga.CALL'
  };
end

local fork = function (func, ...)
  return {
    func = func,
    args = {...},
    moon_effect = 'moon_saga.FORK'
  };
end

local spawn = function (func, ...)
  return {
    func = func,
    args = {...},
    moon_effect = 'moon_saga.SPAWN'
  };
end

local cancel = function (process_id)
  return {
    process_id = process_id,
    moon_effect = 'moon_saga.CANCEL'
  };
end

local race = function (...)
  return {
    racing_effects = {...},
    moon_effect = 'moon_saga.RACE'
  };
end

-- Lib utils --

local uuid = function ()
  local template ='xxxxyyxxxxyyxxyxx';
  return string.gsub(template, '[xy]', function (c)
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb);
    return string.format('%x', v);
  end)
end

local create_process = function (
  iterator,
  parent_id,
  waiting_for,
  paused_until
)
  return {
    id = 'process-'..uuid(),
    iterator = iterator,
    parent_id = parent_id,
    waiting_for = waiting_for or {}, -- forked processes
    paused_until = paused_until, -- action_id or process_id
    finished_iteration = false,
    result_args = nil
  };
end

local collect_coroutine_results = function (resumed, ...)
  local results = {...};
  return resumed, results;
end


-- Main lib functionality --

function M.create()
  local processes = {};
  local logs_enabled = false;
  local saga = {};

  function saga.foreach_processes(...)
    local functions_to_apply = {...};

    for process_id, process
    in pairs(processes)
    do
      for function_index, function_to_apply
      in pairs(functions_to_apply)
      do
        function_to_apply.func(
          process,
          unpack(function_to_apply.args)
        );
      end
    end
  end
  
  function saga.HANDLE_PAUSED_UNTIL(process, until_item_id, ...)
    -- until_item_id is process_id or action_id
    if (process.paused_until == until_item_id) then
      process.paused_until = nil;
      saga.iterate(process, ...);
    end
  end

  function saga.HANDLE_STOP_WAITING_FOR_ATACHED_PROCESS(process, finished_process_id)
    for i = #process.waiting_for, 1, -1 do
      if process.waiting_for[i] == finished_process_id then
        table.remove(process.waiting_for, i);

        if (#process.waiting_for == 0 and process.finished_iteration == true) then
          saga.COMPLETE_PROCESS(process.id);
        end
      end
    end
  end

  function saga.FINISH_PROCESS_ITERATION(process_id, ...)
    local process = processes[process_id];
    process.finished_iteration = true;
    process.result_args = {...};

    if (#process.waiting_for == 0) then
      saga.COMPLETE_PROCESS(process_id);
    end
  end

  function saga.COMPLETE_PROCESS(process_id)
    local process = processes[process_id];

    if (process.finished_iteration) then
      saga.foreach_processes({
        func = saga.HANDLE_PAUSED_UNTIL,
        args = { process_id, unpack(process.result_args) }
      }, {
        func = saga.HANDLE_STOP_WAITING_FOR_ATACHED_PROCESS,
        args = { process_id }
      });

      processes[process.id] = nil;
      collectgarbage();
      return;
    else
      error('Cannot complete process, which didnt finish iteration.');
    end
  end

  function saga.CANCEL_PROCESS(process_id)
    print('cancelling', process_id);

    local waiting_for = processes[process_id].waiting_for;

    for i = #waiting_for, 1, -1 do
      saga.CANCEL_PROCESS(waiting_for[i]);
    end

    local paused_until = processes[process_id].paused_until;
    if (paused_until and processes[paused_until]) then
      -- if paused_until process
      saga.CANCEL_PROCESS(paused_until);
    end

    processes[process_id] = nil;
  end

  -- Effects implementations --

  function saga.DISPATCH(action_id, payload)
    saga.foreach_processes({
      func = saga.HANDLE_PAUSED_UNTIL,
      args = { action_id, payload }
    });
  end

  function saga.TAKE(action_id, process_id)
    processes[process_id].paused_until = action_id;
  end

  function saga.CALL(yielded_effect, parent_id)
    local iterator = coroutine.create(yielded_effect.func);

    local blocking_process = create_process(
      iterator,
      parent_id
    );

    processes[parent_id].paused_until = blocking_process.id;
    saga.iterate(blocking_process, unpack(yielded_effect.args));
  end

  function saga.FORK(yielded_effect, parent_id)
    local iterator = coroutine.create(yielded_effect.func);

    local forked_process = create_process(
      iterator,
      parent_id
    );

    -- register before continue iteration
    processes[forked_process.id] = forked_process;

    table.insert(
      processes[parent_id].waiting_for,
      forked_process.id
    );

    saga.iterate(forked_process, forked_process.id, unpack(yielded_effect.args));
    saga.iterate(processes[parent_id], forked_process.id);
  end

  function saga.SPAWN(yielded_effect, parent_id)
    local iterator = coroutine.create(yielded_effect.func);
    local spawned_process = create_process(iterator);

    -- register before continue iteration
    processes[spawned_process.id] = spawned_process;

    saga.iterate(spawned_process, spawned_process.id, unpack(yielded_effect.args));
    saga.iterate(processes[parent_id], spawned_process.id);
  end

  function saga.RACE(parent_id, yielded_effect)
    local racing_effects = yielded_effect.racing_effects or {};

    saga.run(function ()
      local raced_processes_forks = {};
      local race_output = {};

      local cancel_all_raced_effects = function ()
        for process_index = 1 , #raced_processes_forks, 1 do
          saga.CANCEL_PROCESS(raced_processes_forks[process_index].forked_id);
        end
        
        saga.iterate(parent_id, unpack(race_output))
      end

      for effect_index = 1 , #racing_effects, 1 do
        local effect = racing_effects[effect_index];

        -- validate the effect
        if (not effect_index or type(effect) ~= 'table') then
          error('Some of the effects you specified to RACE is not a valid effect.');
          return;
        end

        raced_processes_forks[effect_index] = {};

        -- fork, resolving the effect
        coroutine.yield(
          fork(function(process_id)
            raced_processes_forks[effect_index] = {
              forked_id = process_id
            };

            local result = { coroutine.yield(effect) };
            -- setting only the finished effect result, others are nil
            race_output[effect_index] = result;
            cancel_all_raced_effects();
          end)
        );
      end
    end);
  end

  function saga.iterate(process, ...)
    if (not processes[process.id]) then
      -- register it if it is a new process
      processes[process.id] = process;
    end

    local resumed, coroutine_results = collect_coroutine_results(
      coroutine.resume(process.iterator, ...)
    );
    
    if (not resumed) then
      error('Cannot resume coroutine...'..unpack(coroutine_results));
      return;
    end

    local yielded_effect = coroutine_results[1];

    local is_valid_effect_yielded =
      type(yielded_effect) == 'table' and
      yielded_effect.moon_effect ~= nil;

    if (is_valid_effect_yielded) then
      if (yielded_effect.moon_effect == 'moon_saga.PUT') then
        saga.DISPATCH(yielded_effect.action_id, yielded_effect.payload);
      elseif (yielded_effect.moon_effect == 'moon_saga.TAKE') then
        return saga.TAKE(yielded_effect.action_id, process.id);
      elseif (yielded_effect.moon_effect == 'moon_saga.CALL') then
        return saga.CALL(yielded_effect, process.id);
      elseif (yielded_effect.moon_effect == 'moon_saga.FORK') then
        return saga.FORK(yielded_effect, process.id);
      elseif (yielded_effect.moon_effect == 'moon_saga.SPAWN') then
        return saga.SPAWN(yielded_effect, process.id);
      elseif (yielded_effect.moon_effect == 'moon_saga.CANCEL') then
        saga.CANCEL_PROCESS(yielded_effect.process_id);
      elseif (yielded_effect.moon_effect == 'moon_saga.RACE') then
        return saga.RACE(process.id, yielded_effect);
      end
    end

    if (coroutine.status(process.iterator) ~= 'dead') then
      return saga.iterate(process);
    else
      saga.FINISH_PROCESS_ITERATION(process.id, unpack(coroutine_results));
    end
  end

  function saga.run(...)
    for key, iterator in pairs({...}) do
      local process = create_process(
        coroutine.create(iterator)
      );

      saga.iterate(process);
    end
  end

  function saga.set_logs(enabled)
    logs_enabled = enabled;
  end

  return {
    set_logs = saga.set_logs,
    run = saga.run,
    put = put,
    take = take,
    call = call,
    fork = fork,
    spawn = spawn,
    cancel = cancel,
    race = race
  };
end

return M;