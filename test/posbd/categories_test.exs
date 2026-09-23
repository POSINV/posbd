defmodule Posbd.CategoriesTest do
  use Posbd.DataCase, async: true

  alias Posbd.Categories

  import Posbd.BusinessesFixtures
  import Posbd.ProductsFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  describe "create_category/2" do
    test "creates a category scoped to the business", %{scope: scope} do
      assert {:ok, category} = Categories.create_category(scope, %{name: "Shirts"})
      assert category.business_id == scope.business.id
      assert category.slug == "shirts"
    end

    test "requires a name", %{scope: scope} do
      assert {:error, changeset} = Categories.create_category(scope, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "supports nested parent categories", %{scope: scope} do
      parent = category_fixture(scope, name: "Clothing")

      assert {:ok, child} =
               Categories.create_category(scope, %{name: "Shirts", parent_id: parent.id})

      assert child.parent_id == parent.id
    end
  end

  describe "tenant isolation" do
    test "a business cannot see another business's categories", %{scope: scope} do
      other_scope = full_scope_fixture()
      category = category_fixture(other_scope)

      refute Categories.get_category(scope, category.id)
      assert Categories.list_categories(scope) == []
    end
  end
end
