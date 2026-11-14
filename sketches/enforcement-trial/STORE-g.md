# The store

`shop.mo` is the module `Shop`. A `Shop` holds four stored tables. Each table is a `Table` of rows, and every row has an `id`.

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
- Every list a table gives comes in order of `id`.

`Shop.sample` is the small shop listed at the end. `Shop.large` is a bigger one.

## Reading a stored table

A stored table can be large, so a `Table` keeps its rows hidden. The compiler refuses code that reaches inside one. A table is read only through these functions.

1. **By key.** `shop.orders.get(id)` gives an `Option` of the row. It works on all four tables.
2. **Through an index.** Each gives an ordinary list of rows.

   | Call | Gives |
   | --- | --- |
   | `shop.customers.in_city(city)` | the customers in that city |
   | `shop.orders.of_customer(customer)` | the orders of that customer |
   | `shop.orders.with_status(status)` | the orders with that status |
   | `shop.orders.total_at_least(least)` | the orders whose total is `least` or more |
   | `shop.orders.placed_between(first, last)` | the orders placed from day `first` to day `last`, both included |
   | `shop.lines.of_order(order)` | the lines of that order |
   | `shop.lines.of_product(product)` | the lines for that product |

3. **By saying that every row must be read.** `shop.orders.walk` gives every row as a list. It works on all four tables. Use it only when the question cannot be answered through an index.

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
