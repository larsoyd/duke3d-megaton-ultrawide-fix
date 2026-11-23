break CONFIG_WriteSetup
commands
  silent
  printf "[integrity] config write called\n"
  continue
end
break dnPushCloudFiles
commands
  silent
  printf "[integrity] cloud upload skipped\n"
  return
  continue
end
continue
