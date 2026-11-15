# The task

`shop.mo` holds the store of a small online shop, and `STORE.md` describes it. So far the shop's code only reads the store. Write `writes.mo`: a module named `Writes` with the functions that change the store, one function for each change that the shop's customers and staff make in an ordinary day. Choose the changes yourself. Write between 6 and 10 functions.

Each function:

- takes the `Shop` as its first parameter and gives back the changed `Shop`;
- gives back the shop unchanged when the change cannot be made, for example when a row it needs is missing;
- takes only `Int`, `Text` and `Status` parameters after the shop;
- names a parameter that holds the id of an existing row after that row's type in lower case: `customer`, `product`, `order` or `line`;
- when it adds a row, adds one row, and takes the new row's id as a parameter named `id`.

Start `writes.mo` like this:

    module Writes
    expose the_names_of_your_functions
    use Shop{Shop}

and add to the braces each other name of `Shop` you use, such as `Order` or `Status`.

Also write `checks.mo`, a module named `Checks` with at least one test of each function on `Shop.sample`, and make `./mo test checks.mo` pass.
