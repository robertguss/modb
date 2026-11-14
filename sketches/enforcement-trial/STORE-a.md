# The store

`shop.mo` is the module `Shop`. A `Shop` holds four stored tables. Each table is a `Map` from a row's `id` to the row.

| Table | Row type | Fields | Indexed fields |
| --- | --- | --- | --- |
| `shop.customers` | `Customer` | `id`, `name`, `city` | `id`, `city` |
| `shop.products` | `Product` | `id`, `name`, `price` | `id` |
| `shop.orders` | `Order` | `id`, `customer`, `status`, `total`, `placed`, `note` | `id`, `customer`, `status`, `total`, `placed` |
| `shop.lines` | `Line` | `id`, `order`, `product`, `quantity` | `id`, `order`, `product` |

- An order's `customer` is the id of a customer. A line's `order` and `product` are the ids of an order and a product.
- `status` is a `Status`: `Open`, `Paid` or `Shipped`.
- `placed` is the number of the day the order was placed. A larger number is a later day.
- `total` and `price` are whole numbers. `note` is free text and may be empty.
- A table's `.values` come in order of `id`.

`Shop.sample` is the small shop listed at the end. `Shop.large` is a bigger one.

## Reading a stored table

A stored table can be large, so the compiler refuses code that would read every row of one. It accepts three ways of reading a table.

1. **By key.** `shop.orders.get(id)` and `shop.orders.has?(id)`.
2. **By a filter on an indexed field.** The test compares one indexed field of the row with a value that does not depend on the row, using `==`, `<`, `<=`, `>` or `>=`. More tests may be joined to it with `and`. The filter is a call of `filter`, `find`, `count` or `any?` on the table's `.values`, or a `for` loop over them whose body is a single `if`. The compiler turns such a filter into an index lookup. What it gives back is an ordinary list, which the rule does not apply to.

       shop.orders.values.filter(fn(order) order.customer == customer end)

3. **By saying that every row must be read.** `walk(shop.orders)` gives the same map with the rule lifted. `walk` comes from `Shop`: `use Shop{Shop, walk}`. Use it only when the question cannot be answered through an index.

## Shop.sample

Customers:

| id | name | city |
| --- | --- | --- |
| 1 | Ada | Lisbon |
| 2 | Ben | Porto |
| 3 | Cy | Lisbon |

Products:

| id | name | price |
| --- | --- | --- |
| 1 | pen | 2 |
| 2 | ink | 5 |
| 3 | pad | 4 |
| 4 | cap | 1 |

Orders:

| id | customer | status | total | placed | note |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | Paid | 12 | 3 | gift wrap |
| 2 | 2 | Open | 5 | 4 | |
| 3 | 1 | Open | 8 | 5 | call first |
| 4 | 1 | Paid | 20 | 5 | a gift |
| 5 | 2 | Shipped | 9 | 1 | leave at door |
| 6 | 1 | Shipped | 4 | 2 | |

Lines:

| id | order | product | quantity |
| --- | --- | --- | --- |
| 1 | 1 | 1 | 1 |
| 2 | 1 | 2 | 2 |
| 3 | 2 | 2 | 1 |
| 4 | 3 | 3 | 2 |
| 5 | 4 | 2 | 4 |
| 6 | 5 | 2 | 1 |
| 7 | 5 | 3 | 1 |
| 8 | 6 | 1 | 2 |
