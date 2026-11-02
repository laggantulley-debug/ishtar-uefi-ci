// Board raw files from Binaries/ishtar: extracted from ishtar's stock HyperOS uefi image (UniXNU-ishtar docs/HANDOFF.md T0).
  FILE FREEFORM = A1E235DE-E825-4591-9623-C43175811826 {
    SECTION UI = "SecParti.cfg"
    SECTION RAW = Binaries/ishtar/RawFiles/SecParti.cfg
  }

!if $(USE_CUSTOM_DISPLAY_DRIVER) == 1
  # Stock ishtar panel data (FFS GUID from the stock image still to be confirmed).
  FILE FREEFORM = 15A84758-9EE1-4543-9C82-F430A70F0813 {
    SECTION UI = "Panel_M1_42_02_0a_ltpo_dsc_cmd.xml"
    SECTION RAW = Binaries/ishtar/RawFiles/Panel_M1_42_02_0a_ltpo_dsc_cmd.xml
  }
!endif
