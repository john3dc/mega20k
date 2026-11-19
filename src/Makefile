.DEFAULT_GOAL := standalone
.PHONY: standalone addon

standalone:
	python3 scripts/build_megadrive20k.py
	python3 scripts/run_megadrive20k.py --check-only

addon:
	python3 scripts/build_megadrive20k.py --addon
	python3 scripts/run_megadrive20k.py --addon --check-only
	python3 scripts/package_core.py build/megadrive20k-addon/megadrive20k.fs build/sd/cores/megadrive20k.bin --id megadrive20k --title "Mega Drive" --autostart
