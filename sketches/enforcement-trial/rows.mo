
enum Status
  Open
  Paid
  Shipped
end

struct Customer
  id: Int
  name: Text
  city: Text
end

struct Product
  id: Int
  name: Text
  price: Int
end

struct Order
  id: Int
  customer: Int
  status: Status
  total: Int
  placed: Int
  note: Text
end

struct Line
  id: Int
  order: Int
  product: Int
  quantity: Int
end

fn customers_by_id(rows: List(Customer)) : Map(Int, Customer)
  var held = {}
  for row in rows
    held = held.set(row.id, row)
  end
  held
end

fn products_by_id(rows: List(Product)) : Map(Int, Product)
  var held = {}
  for row in rows
    held = held.set(row.id, row)
  end
  held
end

fn orders_by_id(rows: List(Order)) : Map(Int, Order)
  var held = {}
  for row in rows
    held = held.set(row.id, row)
  end
  held
end

fn lines_by_id(rows: List(Line)) : Map(Int, Line)
  var held = {}
  for row in rows
    held = held.set(row.id, row)
  end
  held
end

sample = shop_of(
  [
    Customer(id: 1, name: "Ada", city: "Lisbon"),
    Customer(id: 2, name: "Ben", city: "Porto"),
    Customer(id: 3, name: "Cy", city: "Lisbon")
  ],
  [
    Product(id: 1, name: "pen", price: 2),
    Product(id: 2, name: "ink", price: 5),
    Product(id: 3, name: "pad", price: 4),
    Product(id: 4, name: "cap", price: 1)
  ],
  [
    Order(id: 1, customer: 1, status: Paid, total: 12, placed: 3, note: "gift wrap"),
    Order(id: 2, customer: 2, status: Open, total: 5, placed: 4, note: ""),
    Order(id: 3, customer: 1, status: Open, total: 8, placed: 5, note: "call first"),
    Order(id: 4, customer: 1, status: Paid, total: 20, placed: 5, note: "a gift"),
    Order(id: 5, customer: 2, status: Shipped, total: 9, placed: 1, note: "leave at door"),
    Order(id: 6, customer: 1, status: Shipped, total: 4, placed: 2, note: "")
  ],
  [
    Line(id: 1, order: 1, product: 1, quantity: 1),
    Line(id: 2, order: 1, product: 2, quantity: 2),
    Line(id: 3, order: 2, product: 2, quantity: 1),
    Line(id: 4, order: 3, product: 3, quantity: 2),
    Line(id: 5, order: 4, product: 2, quantity: 4),
    Line(id: 6, order: 5, product: 2, quantity: 1),
    Line(id: 7, order: 5, product: 3, quantity: 1),
    Line(id: 8, order: 6, product: 1, quantity: 2)
  ]
)

cities = ["Lisbon", "Porto", "Faro", "Braga", "Evora"]

fn status_of(number: Int) : Status
  case number % 3
    0: Open
    1: Paid
    _: Shipped
  end
end

fn note_of(number: Int) : Text
  case number % 14
    0: "fragile, call first"
    5: "gift wrap"
    10: "a gift"
    _: ""
  end
end

fn large_customers() : List(Customer)
  var rows = []
  for id in 1..41
    rows = rows.append(Customer(id: id, name: "customer #{id}", city: cities.get(id % 5) or "Lisbon"))
  end
  rows
end

fn large_products() : List(Product)
  var rows = []
  for id in 1..26
    rows = rows.append(Product(id: id, name: "product #{(id * 7) % 26}", price: 1 + id % 9))
  end
  rows
end

fn large_orders() : List(Order)
  var rows = []
  for id in 1..301
    rows = rows.append(
      Order(
        id: id,
        customer: 1 + (id * 7) % 37,
        status: status_of(id),
        total: 5 + (id * 13) % 97,
        placed: (id * 11) % 7,
        note: note_of(id)
      )
    )
  end
  rows
end

fn large_lines() : List(Line)
  var rows = []
  for id in 1..901
    rows = rows.append(Line(id: id, order: 1 + id % 300, product: 1 + (id * 5) % 23, quantity: 1 + id % 4))
  end
  rows
end

large = shop_of(large_customers(), large_products(), large_orders(), large_lines())
