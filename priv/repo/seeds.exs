# Populates a demo business for each of several business types, so the
# app has realistic-looking data to develop and demo against without
# manually clicking through onboarding every time.
#
#     mix run priv/repo/seeds.exs
#
# Safe to re-run: each business is skipped (not duplicated) if its owner
# email already exists. Everything here goes through the same contexts
# the API uses (Products, Inventory, Billing, ...), never raw Repo
# inserts, so the seeded data is exactly as valid as anything created
# through the app.

defmodule Posbd.Seeds do
  alias Posbd.{Accounts, Businesses, Categories, Products, Inventory, Billing}
  alias Posbd.Accounts.Scope

  def run(businesses) do
    Enum.each(businesses, &seed_business/1)
  end

  defp seed_business(spec) do
    case Accounts.get_user_by_email(spec.owner_email) do
      %Posbd.Accounts.User{} ->
        IO.puts("skip  #{spec.business_name} - #{spec.owner_email} already exists")

      nil ->
        IO.puts("seed  #{spec.business_name} (#{spec.business_type})")
        do_seed_business(spec)
    end
  end

  defp do_seed_business(spec) do
    {:ok, user} =
      Accounts.register_user(%{
        email: spec.owner_email,
        password: spec.owner_password,
        full_name: spec.owner_name
      })

    user_scope = Scope.for_user(user)

    {:ok, business} =
      Businesses.create_business(user_scope, %{
        name: spec.business_name,
        business_type: spec.business_type,
        country: spec.country,
        currency: spec.currency,
        timezone: spec.timezone,
        language: "en"
      })

    {:ok, business} =
      Businesses.update_business(business, %{
        address: spec.address,
        phone: spec.phone,
        email: spec.business_email,
        tax_number: spec[:tax_number],
        invoice_footer: spec[:invoice_footer] || "Thank you for your business!",
        printer_paper_width: spec[:printer_paper_width] || "80mm",
        printer_font_size: spec[:printer_font_size] || "normal",
        default_print_layout: spec[:default_print_layout] || "thermal"
      })

    {:ok, _} = Businesses.complete_onboarding(business)

    membership = Businesses.get_membership(user_scope, business.id)
    scope = Scope.put_business(user_scope, business, membership)

    categories =
      Map.new(spec.categories, fn name ->
        {:ok, category} = Categories.create_category(scope, %{name: name})
        {name, category}
      end)

    products =
      Enum.map(spec.products, fn product_spec ->
        seed_product(scope, categories, product_spec)
      end)

    seed_invoices(scope, products, spec.sample_sales)

    IO.puts("      login: #{spec.owner_email} / #{spec.owner_password}")
  end

  defp seed_product(scope, categories, spec) do
    {:ok, product} =
      Products.create_product(scope, %{
        name: spec.name,
        category_id: Map.fetch!(categories, spec.category).id,
        brand: spec[:brand],
        unit: spec[:unit] || "pcs",
        tax_rate: spec[:tax_rate] || "0",
        reorder_level: spec[:reorder_level] || 5,
        has_variants: Map.has_key?(spec, :variants),
        sku: if(!Map.has_key?(spec, :variants), do: spec[:sku]),
        purchase_price: if(!Map.has_key?(spec, :variants), do: spec[:purchase_price]),
        selling_price: if(!Map.has_key?(spec, :variants), do: spec[:selling_price]),
        mrp: if(!Map.has_key?(spec, :variants), do: spec[:mrp])
      })

    sellable_items =
      case spec[:variants] do
        nil ->
          {:ok, _txn} =
            Inventory.record_movement(scope, product, %{
              "movement_type" => "opening_stock",
              "direction" => "in",
              "quantity" => spec[:opening_stock] || 20,
              "reference" => "Seed data"
            })

          [{product, nil}]

        variant_specs ->
          Enum.map(variant_specs, fn variant_spec ->
            {:ok, variant} =
              Products.create_variant(scope, product, %{
                "sku" => variant_spec[:sku],
                "purchase_price" => variant_spec[:purchase_price],
                "selling_price" => variant_spec[:selling_price],
                "mrp" => variant_spec[:mrp],
                "attributes" => variant_spec.attributes
              })

            {:ok, _txn} =
              Inventory.record_movement(scope, variant, %{
                "movement_type" => "opening_stock",
                "direction" => "in",
                "quantity" => variant_spec[:opening_stock] || 15,
                "reference" => "Seed data"
              })

            {product, variant}
          end)
      end

    %{product: product, sellable: sellable_items}
  end

  defp seed_invoices(_scope, _products, nil), do: :ok

  defp seed_invoices(scope, products, count) do
    sellable = Enum.flat_map(products, & &1.sellable)

    for _ <- 1..count do
      {product, variant} = Enum.random(sellable)
      quantity = Enum.random(1..3)

      item =
        if variant do
          %{"variant_id" => variant.id, "quantity" => quantity}
        else
          %{"product_id" => product.id, "quantity" => quantity}
        end

      method = Enum.random(["cash", "card", "upi"])

      {:ok, invoice} =
        Billing.create_invoice(scope, %{
          "items" => [item],
          "idempotency_key" => Ecto.UUID.generate()
        })

      {:ok, _} =
        Billing.add_payment(scope, invoice, %{
          "method" => method,
          "amount" => invoice.total_amount
        })
    end
  end
end

Posbd.Seeds.run([
  %{
    owner_name: "Sam Owner",
    owner_email: "owner.clothing@demo.pos",
    owner_password: "DemoPass123!",
    business_name: "Trendy Threads",
    business_type: "clothing",
    business_email: "hello@trendythreads.demo",
    address: "45 Commercial Street, Bengaluru",
    phone: "+91 98450 11223",
    country: "IN",
    currency: "INR",
    timezone: "Asia/Kolkata",
    tax_number: "29TRNDY1234F1Z5",
    categories: ["Men's Wear", "Women's Wear"],
    products: [
      %{
        name: "Classic Cotton T-Shirt",
        category: "Men's Wear",
        brand: "Trendy Threads",
        tax_rate: "5",
        reorder_level: 10,
        variants: [
          %{
            attributes: %{"Size" => "S", "Color" => "Black"},
            sku: "TS-BLK-S",
            purchase_price: "180.00",
            selling_price: "349.00",
            mrp: "399.00",
            opening_stock: 20
          },
          %{
            attributes: %{"Size" => "M", "Color" => "Black"},
            sku: "TS-BLK-M",
            purchase_price: "180.00",
            selling_price: "349.00",
            mrp: "399.00",
            opening_stock: 25
          },
          %{
            attributes: %{"Size" => "L", "Color" => "White"},
            sku: "TS-WHT-L",
            purchase_price: "180.00",
            selling_price: "349.00",
            mrp: "399.00",
            opening_stock: 15
          }
        ]
      },
      %{
        name: "Slim Fit Denim Jeans",
        category: "Men's Wear",
        brand: "Trendy Threads",
        tax_rate: "5",
        reorder_level: 8,
        variants: [
          %{
            attributes: %{"Size" => "30"},
            sku: "JN-30",
            purchase_price: "650.00",
            selling_price: "1299.00",
            mrp: "1499.00",
            opening_stock: 10
          },
          %{
            attributes: %{"Size" => "32"},
            sku: "JN-32",
            purchase_price: "650.00",
            selling_price: "1299.00",
            mrp: "1499.00",
            opening_stock: 12
          },
          %{
            attributes: %{"Size" => "34"},
            sku: "JN-34",
            purchase_price: "650.00",
            selling_price: "1299.00",
            mrp: "1499.00",
            opening_stock: 8
          }
        ]
      },
      %{
        name: "Printed Cotton Saree",
        category: "Women's Wear",
        brand: "Trendy Threads",
        sku: "SAREE-001",
        tax_rate: "5",
        purchase_price: "800.00",
        selling_price: "1450.00",
        mrp: "1699.00",
        opening_stock: 12,
        reorder_level: 4
      }
    ],
    sample_sales: 6
  },
  %{
    owner_name: "Priya Kitchen",
    owner_email: "owner.restaurant@demo.pos",
    owner_password: "DemoPass123!",
    business_name: "Spice Junction",
    business_type: "restaurant",
    business_email: "orders@spicejunction.demo",
    address: "12 Food Street, Chennai",
    phone: "+91 98765 43210",
    country: "IN",
    currency: "INR",
    timezone: "Asia/Kolkata",
    invoice_footer: "GST included. No refunds on food items.",
    categories: ["Starters", "Main Course", "Beverages"],
    products: [
      %{
        name: "Chicken Biryani",
        category: "Main Course",
        unit: "plate",
        tax_rate: "5",
        sku: "BIRYANI",
        purchase_price: "90.00",
        selling_price: "220.00",
        opening_stock: 30,
        reorder_level: 5
      },
      %{
        name: "Paneer Butter Masala",
        category: "Main Course",
        unit: "plate",
        tax_rate: "5",
        sku: "PBM",
        purchase_price: "70.00",
        selling_price: "240.00",
        opening_stock: 25,
        reorder_level: 5
      },
      %{
        name: "Veg Hakka Noodles",
        category: "Starters",
        unit: "plate",
        tax_rate: "5",
        sku: "NOODLES",
        purchase_price: "50.00",
        selling_price: "150.00",
        opening_stock: 25,
        reorder_level: 5
      },
      %{
        name: "Masala Chai",
        category: "Beverages",
        unit: "cup",
        tax_rate: "5",
        sku: "CHAI",
        purchase_price: "8.00",
        selling_price: "30.00",
        opening_stock: 60,
        reorder_level: 10
      }
    ],
    sample_sales: 8
  },
  %{
    owner_name: "Dr. Anita Rao",
    owner_email: "owner.medical@demo.pos",
    owner_password: "DemoPass123!",
    business_name: "City Pharmacy",
    business_type: "medical",
    business_email: "contact@citypharmacy.demo",
    address: "3rd Cross, Hospital Road, Mysuru",
    phone: "+91 94480 22334",
    country: "IN",
    currency: "INR",
    timezone: "Asia/Kolkata",
    tax_number: "29CITYP5678F1Z2",
    invoice_footer: "Medicines once sold are not returnable.",
    invoice_terms: "Please consult a physician before use.",
    # A pharmacy tends to print a fuller itemized bill (batch/expiry-style
    # detail) rather than a quick thermal receipt, and larger text is
    # easier for elderly customers to read - a different default than a
    # clothing shop's 80mm receipt, demonstrating per-business printer config.
    printer_paper_width: "a4",
    printer_font_size: "large",
    default_print_layout: "a4",
    categories: ["Tablets", "Syrups"],
    products: [
      %{
        name: "Paracetamol 500mg (10 tabs)",
        category: "Tablets",
        unit: "strip",
        tax_rate: "12",
        sku: "PARA500",
        purchase_price: "12.00",
        selling_price: "22.00",
        mrp: "25.00",
        opening_stock: 100,
        reorder_level: 20
      },
      %{
        name: "Amoxicillin 250mg (10 tabs)",
        category: "Tablets",
        unit: "strip",
        tax_rate: "12",
        sku: "AMOX250",
        purchase_price: "35.00",
        selling_price: "58.00",
        mrp: "65.00",
        opening_stock: 40,
        reorder_level: 10
      },
      %{
        name: "Cough Syrup 100ml",
        category: "Syrups",
        unit: "bottle",
        tax_rate: "12",
        sku: "COUGH100",
        purchase_price: "45.00",
        selling_price: "75.00",
        mrp: "85.00",
        opening_stock: 30,
        reorder_level: 8
      },
      %{
        name: "Vitamin C Effervescent (10 tabs)",
        category: "Tablets",
        unit: "tube",
        tax_rate: "12",
        sku: "VITC10",
        purchase_price: "60.00",
        selling_price: "99.00",
        mrp: "110.00",
        opening_stock: 25,
        reorder_level: 5
      }
    ],
    sample_sales: 5
  },
  %{
    owner_name: "Ramesh Traders",
    owner_email: "owner.grocery@demo.pos",
    owner_password: "DemoPass123!",
    business_name: "Daily Needs Grocery",
    business_type: "grocery",
    business_email: "store@dailyneeds.demo",
    address: "Main Bazaar Road, Pune",
    phone: "+91 90210 11222",
    country: "IN",
    currency: "INR",
    timezone: "Asia/Kolkata",
    categories: ["Staples", "Beverages"],
    products: [
      %{
        name: "Basmati Rice 5kg",
        category: "Staples",
        unit: "bag",
        tax_rate: "0",
        sku: "RICE5KG",
        purchase_price: "380.00",
        selling_price: "450.00",
        opening_stock: 40,
        reorder_level: 10
      },
      %{
        name: "Refined Sunflower Oil 1L",
        category: "Staples",
        unit: "bottle",
        tax_rate: "5",
        sku: "OIL1L",
        purchase_price: "140.00",
        selling_price: "165.00",
        opening_stock: 50,
        reorder_level: 15
      },
      %{
        name: "Toor Dal 1kg",
        category: "Staples",
        unit: "pack",
        tax_rate: "0",
        sku: "DAL1KG",
        purchase_price: "110.00",
        selling_price: "135.00",
        opening_stock: 45,
        reorder_level: 10
      },
      %{
        name: "Packaged Drinking Water 1L",
        category: "Beverages",
        unit: "bottle",
        tax_rate: "12",
        sku: "WATER1L",
        purchase_price: "8.00",
        selling_price: "20.00",
        opening_stock: 100,
        reorder_level: 20
      }
    ],
    sample_sales: 7
  },
  %{
    owner_name: "Arjun Mehta",
    owner_email: "owner.electronics@demo.pos",
    owner_password: "DemoPass123!",
    business_name: "Gadget Hub",
    business_type: "electronics",
    business_email: "sales@gadgethub.demo",
    address: "Tech Plaza, Sector 18, Noida",
    phone: "+91 99887 66554",
    country: "IN",
    currency: "INR",
    timezone: "Asia/Kolkata",
    tax_number: "09GADGT9012F1Z8",
    categories: ["Mobiles", "Accessories"],
    products: [
      %{
        name: "Wireless Earbuds Pro",
        category: "Accessories",
        brand: "SoundWave",
        tax_rate: "18",
        reorder_level: 6,
        variants: [
          %{
            attributes: %{"Color" => "Black"},
            sku: "EARBUD-BLK",
            purchase_price: "1200.00",
            selling_price: "1999.00",
            mrp: "2499.00",
            opening_stock: 20
          },
          %{
            attributes: %{"Color" => "White"},
            sku: "EARBUD-WHT",
            purchase_price: "1200.00",
            selling_price: "1999.00",
            mrp: "2499.00",
            opening_stock: 15
          }
        ]
      },
      %{
        name: "10000mAh Power Bank",
        category: "Accessories",
        brand: "ChargeIt",
        sku: "PWRBNK10K",
        tax_rate: "18",
        purchase_price: "650.00",
        selling_price: "999.00",
        mrp: "1299.00",
        opening_stock: 30,
        reorder_level: 8
      },
      %{
        name: "USB-C Fast Charging Cable",
        category: "Accessories",
        brand: "ChargeIt",
        sku: "USBC-CBL",
        tax_rate: "18",
        purchase_price: "80.00",
        selling_price: "199.00",
        mrp: "249.00",
        opening_stock: 60,
        reorder_level: 15
      }
    ],
    sample_sales: 6
  }
])

IO.puts("\nSeed complete.")
