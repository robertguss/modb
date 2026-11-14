"""The read tasks of the enforcement trial: what each asks, its example, and what the hidden test sweeps."""

TASKS = [
    {"name": "orders_of", "signature": "fn orders_of(shop: Shop, customer: Int) : List(Int)",
     "asks": "It gives the ids of the customer's orders, smallest first.",
     "example": ["orders_of(Shop.sample, 1) == [1, 3, 4, 6]", "orders_of(Shop.sample, 3) == []"],
     "sweep": ["customer in 0..42"], "call": "orders_of(Shop.large, customer)", "walks": []},
    {"name": "product_name", "signature": "fn product_name(shop: Shop, product: Int) : Option(Text)",
     "asks": "It gives the name of the product with this id, or `None` when there is none.",
     "example": ['product_name(Shop.sample, 2) == Some("ink")', "product_name(Shop.sample, 9) == None"],
     "sweep": ["product in 0..28"], "call": "product_name(Shop.large, product)", "walks": []},
    {"name": "large_orders", "signature": "fn large_orders(shop: Shop, least: Int) : List(Int)",
     "asks": "It gives the ids of the orders whose total is at least `least`, smallest first.",
     "example": ["large_orders(Shop.sample, 9) == [1, 4, 5]"],
     "sweep": ["least in 0..110"], "call": "large_orders(Shop.large, least)", "walks": []},
    {"name": "paid_total", "signature": "fn paid_total(shop: Shop, customer: Int) : Int",
     "asks": "It gives the sum of the totals of the customer's orders whose status is `Paid`.",
     "example": ["paid_total(Shop.sample, 1) == 32", "paid_total(Shop.sample, 2) == 0"],
     "sweep": ["customer in 0..42"], "call": "paid_total(Shop.large, customer)", "walks": []},
    {"name": "open_count", "signature": "fn open_count(shop: Shop) : Int",
     "asks": "It gives how many orders have the status `Open`.",
     "example": ["open_count(Shop.sample) == 2"],
     "sweep": [], "call": "open_count(Shop.large)", "walks": []},
    {"name": "bought", "signature": "fn bought(shop: Shop, customer: Int) : List(Text)",
     "asks": "It gives the names of the products on the customer's orders, each name once, in alphabetical order.",
     "example": ['bought(Shop.sample, 1) == ["ink", "pad", "pen"]', "bought(Shop.sample, 3) == []"],
     "sweep": ["customer in 0..42"], "call": "bought(Shop.large, customer)", "walks": []},
    {"name": "units_sold", "signature": "fn units_sold(shop: Shop, product: Int) : Int",
     "asks": "It gives the sum of the quantities on every line for this product.",
     "example": ["units_sold(Shop.sample, 2) == 8", "units_sold(Shop.sample, 4) == 0"],
     "sweep": ["product in 0..28"], "call": "units_sold(Shop.large, product)", "walks": []},
    {"name": "latest", "signature": "fn latest(shop: Shop, customer: Int, n: Int) : List(Int)",
     "asks": "It gives the ids of the customer's `n` most recently placed orders, the most recent first. "
             "Of two orders placed on the same day, the one with the larger id comes first. "
             "A customer with fewer than `n` orders gives them all.",
     "example": ["latest(Shop.sample, 1, 2) == [4, 3]", "latest(Shop.sample, 2, 5) == [2, 5]"],
     "sweep": ["customer in 0..42", "n in 0..12"], "call": "latest(Shop.large, customer, n)", "walks": []},
    {"name": "mentions", "signature": "fn mentions(shop: Shop, word: Text) : List(Int)",
     "asks": "It gives the ids of the orders whose note contains `word`, smallest first.",
     "example": ['mentions(Shop.sample, "gift") == [1, 4]', 'mentions(Shop.sample, "zebra") == []'],
     "sweep": ['word in ["gift", "call", "wrap", "fragile", "zebra"]'], "call": "mentions(Shop.large, word)",
     "walks": ["orders"]},
    {"name": "idle_customers", "signature": "fn idle_customers(shop: Shop) : List(Int)",
     "asks": "It gives the ids of the customers who have no orders, smallest first.",
     "example": ["idle_customers(Shop.sample) == [3]"],
     "sweep": [], "call": "idle_customers(Shop.large)", "walks": ["customers"]},
]

PILOT = {"name": "city_customers", "signature": "fn city_customers(shop: Shop, city: Text) : List(Text)",
         "asks": "It gives the names of the customers in this city, in alphabetical order.",
         "example": ['city_customers(Shop.sample, "Lisbon") == ["Ada", "Cy"]'],
         "sweep": ['city in ["Lisbon", "Porto", "Faro", "Braga", "Evora", "Rome"]'],
         "call": "city_customers(Shop.large, city)", "walks": []}


def task_text(task):
    example = "\n".join(f"    {line}" for line in task["example"])
    return f"""# The task

Write `answer.mo`: a module named `Answer` that exposes one function.

    {task["signature"]}

{task["asks"]}

On `Shop.sample`, which `STORE.md` lists:

{example}

`example.mo` tests exactly that. Start `answer.mo` like this:

    module Answer
    expose {task["name"]}
    use Shop{{Shop}}
"""


def asserts(task, module):
    return "\n".join(f"  assert {module}.{line}" for line in task["example"])


def example_test(task):
    return f'module Example\nuse Answer\nuse Shop\n\ntest "the example in TASK.md"\n{asserts(task, "Answer")}\nend\n'


def swept(task, line):
    """`line` inside the task's loops, one loop for each thing its hidden test sweeps."""
    depth = len(task["sweep"])
    loops = "".join(f"{'  ' * (at + 1)}for {header}\n" for at, header in enumerate(task["sweep"]))
    ends = "".join(f"{'  ' * at}end\n" for at in range(depth, 0, -1))
    return f"{loops}{'  ' * (depth + 1)}{line}\n{ends}"


def hidden_test(task):
    compare = swept(task, f"assert Answer.{task['call']} == Reference.{task['call']}")
    return (f'module Hidden\nuse Answer\nuse Reference\nuse Shop\n\ntest "hidden"\n{asserts(task, "Answer")}\n'
            f"{compare}end\n")


def printer(tasks):
    """A program that prints every answer the hidden tests compare, for checking that the two arms agree."""
    prints = "".join(swept(task, f'console.print("#{{Reference.{task["call"]}}}")') for task in tasks)
    return f"module Main\nuse Reference\nuse Shop\n\nfn main(console: Console) : Int\n{prints}  0\nend\n"
