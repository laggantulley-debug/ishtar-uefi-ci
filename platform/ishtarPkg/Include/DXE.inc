  INF MdeModulePkg/Core/Dxe/DxeMain.inf
  INF MdeModulePkg/Universal/PCD/Dxe/Pcd.inf

!if $(ISHTAR_VENDOR_HW) == 1
  INF Binaries/ishtar/QcomPkg/Drivers/EnvDxe/EnvDxe.inf
!endif

  INF MdeModulePkg/Universal/ReportStatusCodeRouter/RuntimeDxe/ReportStatusCodeRouterRuntimeDxe.inf
  INF MdeModulePkg/Universal/StatusCodeHandler/RuntimeDxe/StatusCodeHandlerRuntimeDxe.inf
  INF ArmPkg/Drivers/CpuDxe/CpuDxe.inf
  INF MdeModulePkg/Core/RuntimeDxe/RuntimeDxe.inf
  INF MdeModulePkg/Universal/SecurityStubDxe/SecurityStubDxe.inf

!if $(ISHTAR_VENDOR_HW) == 1
  INF Binaries/ishtar/QcomPkg/Drivers/ShmBridgeDxe/ShmBridgeDxeLA.inf
  INF Binaries/ishtar/QcomPkg/Drivers/TzDxe/ScmDxeCompat.inf
  INF Binaries/ishtar/QcomPkg/Drivers/TzDxe/TzDxeLA.inf
!endif

  INF MdeModulePkg/Universal/WatchdogTimerDxe/WatchdogTimer.inf
  INF MdeModulePkg/Universal/CapsuleRuntimeDxe/CapsuleRuntimeDxe.inf
  INF MdeModulePkg/Universal/Variable/RuntimeDxe/VariableRuntimeDxe.inf
  INF EmbeddedPkg/EmbeddedMonotonicCounter/EmbeddedMonotonicCounter.inf
  INF MdeModulePkg/Universal/ResetSystemRuntimeDxe/ResetSystemRuntimeDxe.inf
  INF EmbeddedPkg/RealTimeClockRuntimeDxe/RealTimeClockRuntimeDxe.inf
  INF EmbeddedPkg/MetronomeDxe/MetronomeDxe.inf
  INF MdeModulePkg/Universal/HiiDatabaseDxe/HiiDatabaseDxe.inf
  INF ArmPkg/Drivers/ArmGicDxe/ArmGicDxe.inf
  INF ArmPkg/Drivers/TimerDxe/TimerDxe.inf

!if $(ISHTAR_VENDOR_HW) == 1
  INF Binaries/ishtar/QcomPkg/Drivers/ChipInfoDxe/ChipInfoDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/IPCCDxe/IPCCDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/GLinkDxe/GLinkDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/PlatformInfoDxe/PlatformInfoDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/ProjectInfoDxe/ProjectInfoDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/DALSYSDxe/DALSYSDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/HALIOMMUDxe/HALIOMMUDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/HWIODxe/HWIODxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/I2CDxe/I2CDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/TLMMDxe/TLMMDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/PmicDxe/PmicDxeLa.inf
!endif

  INF MdeModulePkg/Universal/DevicePathDxe/DevicePathDxe.inf
  INF ishtarPkg/Drivers/IshtarBootMemoryDxe/IshtarBootMemoryDxe.inf
  # HakiOS route (uefi-ishtar/HOOK-PORT.md): no in-firmware XNU loader driver.
  # The loader is the patched SiliciumPkg BootManagerLib + XnuLoader.c, which BDS
  # calls directly; an image loaded from a volume is refused by this build's
  # verification, which is why the R3 route put DarwinBoot.inf here.
  INF MdeModulePkg/Universal/Disk/DiskIoDxe/DiskIoDxe.inf
  INF MdeModulePkg/Universal/Disk/PartitionDxe/PartitionDxe.inf
  INF FatPkg/EnhancedFatDxe/Fat.inf
  INF MdeModulePkg/Universal/Disk/UnicodeCollation/EnglishDxe/EnglishDxe.inf

!if $(ISHTAR_VENDOR_HW) == 1
  INF Binaries/ishtar/QcomPkg/Drivers/UFSDxe/UFSDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/CmdDbDxe/CmdDbDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/PwrUtilsDxe/PwrUtilsDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/RpmhDxe/RpmhDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/NpaDxe/NpaDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/ULogDxe/ULogDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/VcsDxe/VcsDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/ClockDxe/ClockDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/SPMIDxe/SPMIDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/ICBDxe/ICBDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/SmemDxe/SmemDxe.inf
!endif
  INF MdeModulePkg/Universal/BdsDxe/BdsDxe.inf

!if $(ISHTAR_VENDOR_HW) == 1
  INF Binaries/ishtar/QcomPkg/Drivers/RscDxe/RscDxe.inf
!endif

  INF EmbeddedPkg/SimpleTextInOutSerial/SimpleTextInOutSerial.inf
  INF MdeModulePkg/Universal/PrintDxe/PrintDxe.inf
  INF MdeModulePkg/Universal/Console/ConPlatformDxe/ConPlatformDxe.inf
  INF MdeModulePkg/Universal/Console/ConSplitterDxe/ConSplitterDxe.inf
  INF ishtarPkg/Drivers/IshtarKeyInputDxe/IshtarKeyInputDxe.inf
  INF MdeModulePkg/Universal/Console/GraphicsConsoleDxe/GraphicsConsoleDxe.inf

  # Vendor peripherals stay off with ISHTAR_VENDOR_HW = 0.
!if $(ISHTAR_VENDOR_HW) == 1
  INF Binaries/ishtar/QcomPkg/Drivers/GpiDxe/GpiDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/SPIDxe/SPIDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/SdccDxe/SdccDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/FeatureEnablerDxe/FeatureEnablerDxe.inf

  # USE_CUSTOM_DISPLAY_DRIVER = 1: stock display chain (board DEPEX glue,
  # unchanged vendor DisplayDxe with the M1 panel data from RAW.inc).
  # Otherwise SimpleFbDxe publishes a GOP on the frame buffer the previous
  # stage left scanning out.
!endif
!if $(USE_CUSTOM_DISPLAY_DRIVER) == 1
  INF ishtarPkg/Drivers/IshtarGopLogDxe/IshtarGopLogDxe.inf
  INF ishtarPkg/Drivers/IshtarDisplayDepexDxe/IshtarDisplayDepexDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/DisplayDxe/DisplayDxe.inf
!else
  INF SiliciumPkg/Drivers/SimpleFbDxe/SimpleFbDxe.inf
!endif

  # Vendor peripherals stay off with ISHTAR_VENDOR_HW = 0.

!if $(ISHTAR_VENDOR_HW) == 1
  INF Binaries/ishtar/QcomPkg/Drivers/ButtonsDxe/ButtonsDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/ChargerExDxe/ChargerExDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/PmicGlinkDxe/PmicGlinkDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/QcomChargerDxe/QcomChargerDxeLA.inf
  INF Binaries/ishtar/QcomPkg/Drivers/UsbPwrCtrlDxe/UsbPwrCtrlDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/TsensDxe/TsensDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/LimitsDxe/LimitsDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/DDRInfoDxe/DDRInfoDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/UsbfnDwc3Dxe/UsbfnDwc3Dxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/XhciPciEmulationDxe/XhciPciEmulationDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/XhciDxe/XhciDxe.inf
!endif

  INF MdeModulePkg/Bus/Usb/UsbBusDxe/UsbBusDxe.inf
  INF MdeModulePkg/Bus/Usb/UsbKbDxe/UsbKbDxe.inf
  INF MdeModulePkg/Bus/Usb/UsbMassStorageDxe/UsbMassStorageDxe.inf

!if $(ISHTAR_VENDOR_HW) == 1
  INF Binaries/ishtar/QcomPkg/Drivers/UsbMsdDxe/UsbMsdDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/UsbDeviceDxe/UsbDeviceDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/UsbConfigDxe/UsbConfigDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/UsbInitDxe/UsbInitDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/UCDxe/UCDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/RNGDxe/RngDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/PILDxe/PILDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/PILProxyDxe/PILProxyDxe.inf
  INF Binaries/ishtar/QcomPkg/Drivers/SPSSDxe/SPSSDxe.inf
!endif
