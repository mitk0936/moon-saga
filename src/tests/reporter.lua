local config = function (test)
  local passing_check = '[32m✔[0m ';
  local failing_check = '[31m✘[0m ';

  local tests_data = { };
  local current_running = 1;
  local current_runing_index = 0;
  local clock = os.clock();

  test(function (event, func_name, msg)
    local prefix = string.rep('      ', current_running);

    if (event == 'begin') then

      table.insert(tests_data, {
        name = func_name,
        successes = 0,
        failures = {},
        level = current_running
      });

      current_running = current_running + 1;
    elseif (event == 'pass') then
      tests_data[#tests_data].successes = tests_data[#tests_data].successes + 1;
    elseif (event == 'fail' or event == 'except') then
      table.insert(tests_data[#tests_data].failures, { error = msg });
    elseif (event == 'end') then
      current_running = current_running - 1;
    end
  end);

  return function ()
    local failed = 0;
    local successes = 0;
    local tests_timing = os.clock() - clock;

    for test_name, test_data in pairs(tests_data) do
      local prefix = string.rep('  ', test_data.level);

      if (test_data.successes > 0) then
        print(prefix..passing_check..''..test_data.name..prefix..'['..test_data.successes..'] checks passed');
        successes = successes + test_data.successes;
      end

      if (#test_data.failures > 0) then
        failed = failed + #test_data.failures;

        for index, failure in pairs(test_data.failures) do
          print(prefix);
          print(prefix..failing_check..''..test_data.name);
          print(prefix..failure.error);
          print(prefix);
        end
      end

      if (test_data.successes == 0 and #test_data.failures == 0) then
        print(prefix..passing_check..''..test_data.name, '[0 checks]');
      end
    end

    print('\n');
    print('Results:');
    print(passing_check..'Passed: ', successes);
    print(failing_check..'Failed: ', failed);
    print('Total checks: ', successes + failed);

    print('Tests completed in: '..tests_timing..' seconds.')

    os.exit(failed);
  end
end

return config;