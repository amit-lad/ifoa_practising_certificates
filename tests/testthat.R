# Run the tests from the repository root with: Rscript tests/testthat.R
library(testthat)

test_dir("tests/testthat", stop_on_failure = TRUE)
