# Development Instructions

Use test-driven development for production changes.

1. Write or update a test that describes the intended observable behavior before
   implementing the behavior.
2. Run the focused test and confirm that it fails for the expected reason.
3. Implement the smallest change that makes the test pass.
4. Refactor only while the relevant tests remain green.

For bugs, begin with a regression test. Keep tests focused on behavior and avoid
tests that only mirror implementation details. Run the relevant test suite before
submitting work for review.
