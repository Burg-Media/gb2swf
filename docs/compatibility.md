# Compatibility

Measured on 2026-10-13 with gb2swf 1.0.0, Ruffle 0.8.0-nightly.2026.10.11, headless Chrome on
macOS (Apple M1). Everything in this file is produced by
`node scripts/compat-report.mjs` and can be reproduced with the same files.

## Homebrew games

All games below have open licenses that allow redistribution; see each game's page.
"Recompiled" is the share of executed instructions that ran as recompiled code on
an input sequence the profiler had not seen (the rest ran on the interpreter).
"ms/frame" is the time the SWF spent per Game Boy frame (emulation, sound and
picture); the budget for full speed is 16.7 ms. Measured during the first seconds
of play with automated input, so the numbers describe that scene, not the whole game.

| Game | License | Link | Works | Recompiled | fps in Ruffle | ms/frame | SWF size | Notes |
|---|---|---|---|---|---|---|---|---|
| Tobu Tobu Girl (DMG) | Code MIT, assets CC BY 4.0 | https://tangramgames.itch.io/tobutobugirl | yes | 97.3% | 59 | 7.7 | 258 KiB |  |
| Tobu Tobu Girl Deluxe (CGB+DMG) | Code MIT, assets CC BY 4.0 | https://tangramgames.itch.io/tobu-tobu-girl-deluxe | yes | 97.1% | 60 | 7.6 | 302 KiB |  |
| Libbet and the Magic Floor (CGB+DMG) | zlib | https://github.com/pinobatch/libbet | yes | 96.6% | 61 | 10.9 | 75 KiB |  |
| µCity (CGB only) | Code GPL-3.0-or-later (GBT Player BSD-2-Clause), media CC BY-SA 4.0 | https://github.com/AntonioND/ucity | yes | 97.5% | 61 | 6.4 | 291 KiB | Game Boy Color only; 128 KiB battery RAM |
| Geometrix (CGB+DMG) | GPL-3.0-or-later | https://github.com/AntonioND/geometrix | yes | 97.4% | 59 | 6.9 | 82 KiB |  |
| Big2Small (CGB+DMG) | Code GPL-3.0-or-later; assets CC BY 4.0 (per the author's itch.io page) | https://github.com/mdsteele/big2small | yes | 78.9% | 60 | 8.1 | 107 KiB | about a fifth of the executed code runs from RAM (copied there by the game), which is always interpreted |
| Dawn Will Come (CGB only) | Code MIT (GB Studio engine (c) Chris Maltby), art and music CC BY 4.0 | https://eishiya.itch.io/dawn-will-come | yes | 98.4% | 60 | 8.3 | 545 KiB | contains horror themes (gore); 2 MiB GB Studio game |

"Works" means: the build passed the interpreter-vs-recompiled check, the game ran
at full speed in Ruffle without errors, and the page loaded only its own local
files. It does not mean every level was played through.

## Test ROMs

Interpreter: the ROM run on gb2swf's interpreter. Recompiled: the ROM profiled,
recompiled, checked and run from its recompiled code (not run for Mooneye and
rtc3test). Failures listed with a reason are known limitations.

| Suite | Test ROM | Model | Interpreter | Recompiled | Notes |
|---|---|---|---|---|---|
| Blargg | cpu_instrs/cpu_instrs.gb | CGB | pass | pass | rec share ~2% |
| Blargg | instr_timing/instr_timing.gb | CGB | pass | pass | rec share ~6% |
| Blargg | mem_timing/mem_timing.gb | CGB | pass | pass | rec share ~44% |
| Blargg | mem_timing-2/mem_timing.gb | CGB | pass | pass | rec share ~69% |
| Blargg | halt_bug.gb | CGB | pass | pass | result read from screen; rec share ~1% |
| Blargg | interrupt_time/interrupt_time.gb | CGB | pass | pass | result read from screen; rec share ~0% |
| Blargg | oam_bug/oam_bug.gb | CGB | fail | fail | OAM corruption bug of the DMG is not emulated; Failed #2; rec share ~20% |
| Blargg | dmg_sound/dmg_sound.gb | DMG | fail | fail | 6 of 12 sub-tests fail (trigger, sweep details, length counter at power-on, wave RAM access while playing, register values after power-on); Failed #3; rec share ~15% |
| Blargg | cgb_sound/cgb_sound.gb | CGB | fail | fail | same sound-chip details as dmg_sound; Failed #3; rec share ~15% |
| acid2 | dmg-acid2.gb | DMG | pass | pass | rec share ~100% |
| acid2 | cgb-acid2.gbc | CGB | pass | pass | rec share ~100% |
| Mooneye | acceptance/add_sp_e_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/bits/mem_oam.gb | DMG | pass | not run |  |
| Mooneye | acceptance/bits/reg_f.gb | DMG | pass | not run |  |
| Mooneye | acceptance/bits/unused_hwio-GS.gb | DMG | pass | not run |  |
| Mooneye | acceptance/boot_div-dmgABCmgb.gb | DMG | fail | not run | exact DIV phase after the boot ROM |
| Mooneye | acceptance/boot_hwio-dmgABCmgb.gb | DMG | fail | not run | IO register values after the boot ROM |
| Mooneye | acceptance/boot_regs-dmgABC.gb | DMG | pass | not run |  |
| Mooneye | acceptance/call_cc_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/call_cc_timing2.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/call_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/call_timing2.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/di_timing-GS.gb | DMG | fail | not run | interrupt dispatch timing |
| Mooneye | acceptance/div_timing.gb | DMG | pass | not run |  |
| Mooneye | acceptance/ei_sequence.gb | DMG | pass | not run |  |
| Mooneye | acceptance/ei_timing.gb | DMG | pass | not run |  |
| Mooneye | acceptance/halt_ime0_ei.gb | DMG | pass | not run |  |
| Mooneye | acceptance/halt_ime0_nointr_timing.gb | DMG | pass | not run |  |
| Mooneye | acceptance/halt_ime1_timing.gb | DMG | pass | not run |  |
| Mooneye | acceptance/halt_ime1_timing2-GS.gb | DMG | fail | not run | interrupt dispatch timing |
| Mooneye | acceptance/if_ie_registers.gb | DMG | pass | not run |  |
| Mooneye | acceptance/instr/daa.gb | DMG | pass | not run |  |
| Mooneye | acceptance/interrupts/ie_push.gb | DMG | pass | not run |  |
| Mooneye | acceptance/intr_timing.gb | DMG | pass | not run |  |
| Mooneye | acceptance/jp_cc_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/jp_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/ld_hl_sp_e_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/oam_dma/basic.gb | DMG | pass | not run |  |
| Mooneye | acceptance/oam_dma/reg_read.gb | DMG | fail | not run | OAM DMA is instantaneous |
| Mooneye | acceptance/oam_dma/sources-GS.gb | DMG | fail | not run | OAM DMA is instantaneous |
| Mooneye | acceptance/oam_dma_restart.gb | DMG | fail | not run | OAM DMA is instantaneous |
| Mooneye | acceptance/oam_dma_start.gb | DMG | fail | not run | OAM DMA is instantaneous |
| Mooneye | acceptance/oam_dma_timing.gb | DMG | fail | not run | OAM DMA is instantaneous |
| Mooneye | acceptance/pop_timing.gb | DMG | pass | not run |  |
| Mooneye | acceptance/ppu/hblank_ly_scx_timing-GS.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/intr_1_2_timing-GS.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/intr_2_0_timing.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/intr_2_mode0_timing.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/intr_2_mode0_timing_sprites.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/intr_2_mode3_timing.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/intr_2_oam_ok_timing.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/lcdon_timing-GS.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/lcdon_write_timing-GS.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/stat_irq_blocking.gb | DMG | pass | not run |  |
| Mooneye | acceptance/ppu/stat_lyc_onoff.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/ppu/vblank_stat_intr-GS.gb | DMG | fail | not run | PPU timing is per scanline (mode 3 has a fixed length); these tests need dot-exact timing |
| Mooneye | acceptance/push_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/rapid_di_ei.gb | DMG | pass | not run |  |
| Mooneye | acceptance/ret_cc_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/ret_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/reti_intr_timing.gb | DMG | pass | not run |  |
| Mooneye | acceptance/reti_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/rst_timing.gb | DMG | fail | not run | OAM DMA bus conflicts are not emulated (the test detects instruction fetch timing through them) |
| Mooneye | acceptance/timer/div_write.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/rapid_toggle.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tim00.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tim00_div_trigger.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tim01.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tim01_div_trigger.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tim10.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tim10_div_trigger.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tim11.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tim11_div_trigger.gb | DMG | pass | not run |  |
| Mooneye | acceptance/timer/tima_reload.gb | DMG | fail | not run | TIMA reload delay of one M-cycle |
| Mooneye | acceptance/timer/tima_write_reloading.gb | DMG | fail | not run | TIMA reload delay of one M-cycle |
| Mooneye | acceptance/timer/tma_write_reloading.gb | DMG | fail | not run | TIMA reload delay of one M-cycle |
| Mooneye | emulator-only/mbc1/bits_bank1.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/bits_bank2.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/bits_mode.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/bits_ramg.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/multicart_rom_8Mb.gb | DMG | fail | not run | MBC1 multicart wiring (MBC1M) is not detected |
| Mooneye | emulator-only/mbc1/ram_256kb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/ram_64kb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/rom_16Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/rom_1Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/rom_2Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/rom_4Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/rom_512kb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc1/rom_8Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc2/bits_ramg.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc2/bits_romb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc2/bits_unused.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc2/ram.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc2/rom_1Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc2/rom_2Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc2/rom_512kb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc5/rom_16Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc5/rom_1Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc5/rom_2Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc5/rom_32Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc5/rom_4Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc5/rom_512kb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc5/rom_64Mb.gb | DMG | pass | not run |  |
| Mooneye | emulator-only/mbc5/rom_8Mb.gb | DMG | pass | not run |  |
| rtc3test | rtc3test.gb | CGB | pass | not run | basic, range and sub-second pages all green |

