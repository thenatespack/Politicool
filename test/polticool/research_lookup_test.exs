defmodule Polticool.ResearchLookupTest do
  # Card 950: live research only searched the local candidates table, so any
  # legislator on the le.utah.gov roster without a candidate row was "not found".
  use PolticoolWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Polticool.{Ballot, Repo, Research}
  alias Polticool.Ballot.Candidate

  # Cached mode with an empty cache dir: a found legislator starts a replay that
  # fails cleanly, so no test reaches le.utah.gov or Anthropic.
  setup do
    dir = Path.join(System.tmp_dir!(), "research-lookup-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    old_dir = Application.get_env(:polticool, :research_cache_dir)
    Application.put_env(:polticool, :research_cache_dir, dir)
    Application.put_env(:polticool, :research_mode, :cached)
    Application.put_env(:polticool, :research_replay_delay_ms, 0)

    on_exit(fn ->
      Application.put_env(:polticool, :research_cache_dir, old_dir)
      Application.put_env(:polticool, :research_mode, :live)
      File.rm_rf!(dir)
    end)
  end

  test "a roster legislator with no candidate row is found by last name" do
    assert {:ok, _run} = Research.start("Whyte")

    assert %Candidate{name: "Stephen L. Whyte", party: "R", office: "Utah House", district: "63"} =
             Repo.get_by!(Candidate, le_code: "WHYTESL")
  end

  test "a roster legislator is found by legislator code" do
    assert {:ok, _run} = Research.start("THOMJA")
    assert Repo.get_by!(Candidate, le_code: "THOMJA").name == "Jason E. Thompson"
  end

  test "researching the same legislator twice reuses the candidate row" do
    assert {:ok, _} = Research.start("Whyte")
    assert {:ok, _} = Research.start("Whyte")
    assert Repo.aggregate(Candidate, :count) == 1
  end

  test "an ambiguous name lists roster legislators, pickable by code" do
    assert {:ambiguous, list} = Research.start("Miller")
    assert list |> Enum.map(& &1.le_code) |> Enum.sort() == ["MILLET", "MILLGR"]
    assert Enum.all?(list, &(&1.office == "Utah House"))
    assert Repo.aggregate(Candidate, :count) == 0

    assert {:ok, _} = Research.start("MILLGR")
    assert Repo.get_by!(Candidate, le_code: "MILLGR").name == "Grant Amjad Miller"
  end

  test "a candidate already in the database isn't listed twice" do
    %Candidate{}
    |> Candidate.changeset(%{name: "Norman Thurston", le_code: "THURSNK"})
    |> Repo.insert!()

    assert {:ok, _} = Research.start("Thurston")
    assert Repo.aggregate(Candidate, :count) == 1
  end

  test "researched legislators don't show up as races on the ballot" do
    assert {:ok, _} = Research.start("Whyte")
    assert Ballot.list_races() == []
  end

  test "names on neither the roster nor the database are still not found" do
    assert {:error, :not_found} = Research.start("Zzyzx")
  end

  test "the research page starts a run for a roster legislator and picks by code", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/research")

    view |> form("#research-form", research: %{name: "Whyte"}) |> render_submit()
    refute has_element?(view, "#research-error")
    assert has_element?(view, "#research-run")

    view |> form("#research-form", research: %{name: "Miller"}) |> render_submit()
    assert has_element?(view, "#research-picker #pick-MILLGR")

    view |> element("#pick-MILLGR") |> render_click()
    refute has_element?(view, "#research-picker")
    assert has_element?(view, "#research-run")
  end
end
