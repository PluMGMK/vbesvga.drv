# Assembled-code regression test

Build `VDDVBE.386` using the DDK procedure in the main README, retaining its
matching `VDDVGA.MAP`. Install Python 3, `capstone` and `unicorn`, then run:

```
python3 tests/test_service_dispatch.py --binary /path/to/VDDVBE.386 --map /path/to/VDDVGA.MAP
```

The test executes the built dispatcher, with a successful VMM validation call
at its OS boundary, and checks both valid destinations and invalid full-width
service numbers. It needs no Windows installation or proprietary tools beyond
those used for the documented build. It does not emulate the VMM itself.
