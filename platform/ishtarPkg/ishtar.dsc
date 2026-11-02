##
#  Copyright (c) 2011 - 2022, ARM Limited. All rights reserved.
#  Copyright (c) 2014, Linaro Limited. All rights reserved.
#  Copyright (c) 2015 - 2020, Intel Corporation. All rights reserved.
#  Copyright (c) 2018, Bingxing Wang. All rights reserved.
#  Copyright (c) Microsoft Corporation.
#
#  SPDX-License-Identifier: BSD-2-Clause-Patent
##

################################################################################
#
# Defines Section - statements that will be processed to create a Makefile.
#
################################################################################
[Defines]
  PLATFORM_NAME                  = ishtar
  PLATFORM_GUID                  = F9728C5D-4394-4AC0-97DE-BCC5DBC6F23F
  PLATFORM_VERSION               = 0.1
  DSC_SPECIFICATION              = 0x00010005
  OUTPUT_DIRECTORY               = Build/ishtarPkg
  SUPPORTED_ARCHITECTURES        = AARCH64
  BUILD_TARGETS                  = RELEASE|DEBUG
  SKUID_IDENTIFIER               = DEFAULT
  FLASH_DEFINITION               = ishtarPkg/ishtar.fdf
  USE_CUSTOM_DISPLAY_DRIVER      = 0

  #
  # 0 = Mu drivers only. The previous stage's display keeps scanning out, so
  #     the boot manager is visible without any vendor hardware driver.
  # 1 = also load the stock vendor hardware drivers from Binaries/ishtar. On sheng
  #     the equivalent set blanks the panel; untested here.
  #
  ISHTAR_VENDOR_HW                = 0

  #
  # 0 = SM8550-AB
  # 1 = SM8550-AC
  #
  SOC_TYPE                       = 0

!include KailuaPkg/KailuaPkg.dsc.inc

!if ($(USE_CUSTOM_DISPLAY_DRIVER) == 1) && ($(ISHTAR_VENDOR_HW) == 0)
  !error The stock DisplayDxe chain needs ISHTAR_VENDOR_HW = 1
!endif

[PcdsFixedAtBuild]
  #
  # DDR Memory
  #
  gArmTokenSpaceGuid.PcdSystemMemoryBase|0x80000000

  #
  # UEFI Stack
  #
  gArmPlatformTokenSpaceGuid.PcdCPUCoresStackBase|0xA760D000
  gArmPlatformTokenSpaceGuid.PcdCPUCorePrimaryStackSize|0x40000

  #
  # SMBIOS
  #
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemManufacturer|"Xiaomi"
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemModel|"ishtar"
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemRetailModel|"ishtar"
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemRetailSku|"ishtar"
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemBoardModel|"ishtar"

  #
  # Simple Frame Buffer
  #
  # Panel M1 42 02 0a (Binaries/ishtar/RawFiles/Panel_M1_42_02_0a_ltpo_dsc_cmd.xml):
  # 1440x3200, DSC command mode, 60 Hz as the stock XBL leaves it. Stride 5760
  # (= width x 4) was measured on the DPU by the old ishtar port.
  #
  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferWidth|1440
  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferHeight|3200
  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferColorDepth|32
  # Scale 2 gives 100 lines of 90 columns. The log wraps, so the screen always shows the
  # newest lines; the platform debug level is left unchanged.
  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferFontScale|2
  # Pause per log line so a video of the screen shows what loads last.
  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferDelay|30000


  #
  # Platform PEI
  #
  gQcomPkgTokenSpaceGuid.PcdPlatformType|"LA"
!if $(ISHTAR_VENDOR_HW) == 0
  # Intermittent stall right after "MMU: enabled" (int-103 photos): PlatformPeim scanned the stock UEFI's leftover FD window and
  # called into its scheduler protocol. Without the stock vendor drivers nothing reads those HOBs.
  gQcomPkgTokenSpaceGuid.PcdBuildXblHobs|FALSE
!endif

[LibraryClasses]
  #
  # Memory Libraries
  #
  MemoryMapLib|ishtarPkg/Library/MemoryMapLib/MemoryMapLib.inf

  #
  # QCOM Libraries
  #
  ConfigurationMapLib|ishtarPkg/Library/ConfigurationMapLib/ConfigurationMapLib.inf

[Components]
  #
  # ACPI Tables
  #
  #
  # HakiOS route (uefi-ishtar/HOOK-PORT.md): the kernel is started by the patched
  # BootManagerLib + XnuLoader.c in SiliciumPkg, not by UniXNU's prelink loader.
  # The uniXNU pieces below were the R3 (prelink) mechanism and are removed so the
  # two routes cannot both claim the USB link and the XNU handoff.
  #
  #   UniXNUPkg/Application/UniXNU/UniXNU.inf
  #   UniXNUPkg/Driver/UniXNUDxe/UniXNUDxe.inf
  #   UniXNUPkg/Driver/UniXNURamDiskDxe/UniXNURamDiskDxe.inf
  #   DarwinBootPkg/Driver/DarwinBoot.inf
  #
  ishtarPkg/Drivers/IshtarDisplayDepexDxe/IshtarDisplayDepexDxe.inf
  ishtarPkg/Drivers/IshtarGopLogDxe/IshtarGopLogDxe.inf
  ishtarPkg/Drivers/IshtarBootMemoryDxe/IshtarBootMemoryDxe.inf
  ishtarPkg/Drivers/IshtarKeyInputDxe/IshtarKeyInputDxe.inf

[LibraryClasses]
  FdtLib|MdePkg/Library/BaseFdtLib/BaseFdtLib.inf
