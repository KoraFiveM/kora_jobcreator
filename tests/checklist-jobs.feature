# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_jobcreator — Jobs

  @kora_jobcreator @checklist @checklist:kora_jobcreator:jobcreator-console @cat:jobs @needs:admin
  Scenario: /jobcreator console
    """
    Checklist test: Run /jobcreator as admin (sees all) or a boss (own business only): searchable business cards, then Overview / Modules / Activity tabs.
    """
    When I run the command "/jobcreator"
    Then the "qbjobcreator:management" app opens
    And I confirm: the console shows searchable business cards (admin sees all businesses, a boss sees only their own)
    When I manually: open a business card
    Then I confirm: the Overview, Modules and Activity tabs are shown

  @kora_jobcreator @checklist @checklist:kora_jobcreator:seed-burgershot @cat:jobs @needs:admin @manual
  Scenario: Demo Burger Shot business
    """
    Checklist test: On a fresh DB a Burger Shot business and burgershot job exist; deleting it in-game keeps it deleted after restart.
    """
    When I manually: on a fresh database, type /jobcreator in chat and look at the business list
    Then I confirm: a Burger Shot business exists and the burgershot job exists
    When I manually: delete the Burger Shot business in-game and restart the resource
    Then I confirm: the Burger Shot business stays deleted after the restart

  @kora_jobcreator @checklist @checklist:kora_jobcreator:add-module-placement @cat:jobs @needs:admin
  Scenario: Add module with in-world placement
    """
    Checklist test: Add a module: pick type, place the zone/prop/ped with the world editor (or press E on an existing object); creator reopens with the coordinates.
    """
    When I manually: type /jobcreator in chat as an admin and open a business
    And I manually: start adding a module and pick its type
    And I manually: place the zone, prop or ped with the world editor, or press E on an existing object
    Then the "qbjobcreator:management" app should be open
    And I confirm: the creator reopens on the same business with the placed coordinates applied

  @kora_jobcreator @checklist @checklist:kora_jobcreator:module-live-sync @cat:jobs @needs:admin @manual
  Scenario: New modules appear live
    """
    Checklist test: Save a module and check another client sees the target/zone immediately with no restart.
    """
    When I manually: type /jobcreator in chat as an admin and save a new module
    And I manually: ask a second player to look at the module location without restarting anything
    Then I confirm: the other player sees the module's target or zone immediately

  @kora_jobcreator @checklist @checklist:kora_jobcreator:edit-data-rebuild @cat:jobs @needs:admin
  Scenario: Edit data / Rebuild a module
    """
    Checklist test: Use Edit data to change a label or price as JSON (validated on save), and Rebuild to change type or re-place the anchor.
    """
    When I manually: type /jobcreator in chat as an admin and open a module
    And I manually: use Edit data to change a label or price in the JSON, then save
    Then I should see a notification containing "Module data saved. It is live now."
    When I manually: use Edit data to enter invalid JSON, then save
    Then I should see a notification containing "That data was rejected."
    When I manually: use Rebuild on the module to change its type or re-place the anchor
    Then I confirm: the module is rebuilt with the new type or anchor

  @kora_jobcreator @checklist @checklist:kora_jobcreator:debug-tab @cat:jobs @needs:admin
  Scenario: Admin Debug tab
    """
    Checklist test: As admin copy business/module JSON and toggle zone and target outlines on your own client only.
    """
    When I manually: type /jobcreator in chat as an admin, open a business and then its Debug tab
    And I manually: copy the business JSON
    Then I should see a notification containing "Business data copied to your clipboard."
    When I manually: select a module and copy its module JSON
    Then I should see a notification containing "Module data copied to your clipboard."
    When I manually: toggle the zone and target outlines
    Then I confirm: outlines show on my client
    And I confirm: the other player does not see the outlines on their screen

  @kora_jobcreator @checklist @checklist:kora_jobcreator:zone-duty @cat:jobs
  Scenario: Perimeter zone clock on/off
    """
    Checklist test: Walk into a business Zone as staff: you are clocked on and modules build; leave and you clock off and they are removed.
    """
    Given my job is "police"
    When I manually: walk into a business perimeter zone as staff
    Then I confirm: I am clocked on and the business modules appear
    When I manually: leave the business perimeter zone
    Then I confirm: I am clocked off and the modules are removed (only applies when Config.duty.enabled is on)

  @kora_jobcreator @checklist @checklist:kora_jobcreator:pos-customer-buy @cat:jobs
  Scenario: Customer buys from till
    """
    Checklist test: At a POS till (Burger Shot) open the shelf as a customer, buy an item; stock reduces and payment is charged.
    """
    Given my cash balance is 500
    When I manually: go to the Burger Shot till
    And I manually: open the shelf as a customer
    And I manually: buy an item from the shelf
    Then I confirm: the stock of that item on the shelf is reduced
    And I confirm: my cash is charged the item price

  @kora_jobcreator @checklist @checklist:kora_jobcreator:pos-intake-stash @cat:jobs @manual
  Scenario: Employee stocks the intake stash
    """
    Checklist test: As staff open the till's intake stash, drop items and close it; you are asked a price per item type and goods move to the shelf.
    """
    When I manually: go to a till as staff and open its intake stash
    And I manually: drop items into the stash and close it
    Then I confirm: I am asked for a price per item type
    And I confirm: the goods move to the shelf

  @kora_jobcreator @checklist @checklist:kora_jobcreator:pos-fixed-prices @cat:jobs @manual
  Scenario: Fixed vs employee-set prices
    """
    Checklist test: Items listed with a price in shop lists are fixed; items without a price prompt the employee, who is remembered next time.
    """
    When I manually: as staff, stock an item that has a price in the shop list into the till stash
    Then I confirm: I am not asked for a price and the listed fixed price is used
    When I manually: stock an item without a listed price into the till stash and enter a price
    Then I confirm: I am prompted for the price
    When I manually: stock the same item again later
    Then I confirm: the price I set earlier is remembered

  @kora_jobcreator @checklist @checklist:kora_jobcreator:pos-commission-tax @cat:jobs @manual
  Scenario: Commission and tax on sales
    """
    Checklist test: Sell stocked goods: tax is withheld, business account is credited and the stocking employee gets commission only on sold stock.
    """
    When I manually: as staff, stock goods into a till
    And I manually: ask a second player to buy the stocked goods from the till
    Then I confirm: tax is withheld from the sale
    And I confirm: the business account is credited
    And I confirm: the stocking employee gets commission only on the sold stock

  @kora_jobcreator @checklist @checklist:kora_jobcreator:pos-hide-when-staffed @cat:jobs @manual
  Scenario: Self-serve blocked when staffed
    """
    Checklist test: With hideWhenStaffed on and an employee inside the perimeter, customers cannot use the till.
    """
    When I manually: ask a second player to stand inside the business perimeter as an employee
    And I manually: try to use the till as a customer (only applies when hideWhenStaffed is enabled on the module; otherwise mark Pass if nothing happens)
    Then I confirm: I cannot use the till while an employee is inside the perimeter

  @kora_jobcreator @checklist @checklist:kora_jobcreator:pos-panic-button @cat:jobs
  Scenario: Till panic button
    """
    Checklist test: Use the panic option on a till with panicButton: silent alarm sent to police via dispatch.
    """
    When I manually: go to a till module that has panicButton enabled
    And I manually: use the panic option on the till
    Then I should see a notification containing "Silent alarm sent."
    And I confirm: the silent alarm reaches police via dispatch (only applies when kora_dispatch is installed; otherwise mark Pass if "The alarm did not go through." shows)

  @kora_jobcreator @checklist @checklist:kora_jobcreator:job-stash @cat:jobs @manual
  Scenario: Job-locked stash
    """
    Checklist test: Open a Stash module as an employee (works) and as another job (hidden/denied) unless marked public; it closes if you walk away.
    """
    When I manually: open a Stash module of a business while employed in that job
    Then I confirm: the stash opens for me as an employee
    When I manually: ask a second player with a different job to try the same Stash module
    Then I confirm: the other player does not see the stash option or is denied (unless the stash is marked public)
    When I manually: open the stash and walk away from it
    Then I confirm: the stash inventory closes when I walk away

  @kora_jobcreator @checklist @checklist:kora_jobcreator:crafting-bench @cat:jobs
  Scenario: Crafting bench recipes
    """
    Checklist test: Open the Burger Shot bench: recipes show live ingredient counts and grey out when missing; craft shows a progress bar and gives the item.
    """
    When I manually: go to the Burger Shot crafting bench and open it
    Then I confirm: recipes show live ingredient counts for my inventory
    And I confirm: recipes with missing ingredients are greyed out
    When I manually: craft a recipe with all ingredients available
    Then a progress bar should run
    And I confirm: I receive the crafted item

  @kora_jobcreator @checklist @checklist:kora_jobcreator:crafting-rollback @cat:jobs @manual
  Scenario: Craft needs all ingredients
    """
    Checklist test: Try to craft with partial ingredients or from over 8m away: server refuses and nothing is lost.
    """
    When I manually: try to craft a recipe at the bench with only some of the ingredients
    Then I confirm: the server refuses the craft and I lose no items
    When I manually: start a craft and move more than 8m away from the bench
    Then I confirm: the server refuses the craft and I lose no items

  @kora_jobcreator @checklist @checklist:kora_jobcreator:boss-menu-module @cat:jobs @manual
  Scenario: Boss menu desk
    """
    Checklist test: As a boss of the job use the BossMenu target to open the boss menu; non-bosses cannot see the option.
    """
    When I manually: as a boss of the business job, target the BossMenu module
    Then I confirm: the boss menu opens
    When I manually: ask a second player who is not a boss to look at the BossMenu module
    Then I confirm: the other player does not see the BossMenu target option

  @kora_jobcreator @checklist @checklist:kora_jobcreator:useable-item-reward @cat:jobs @manual
  Scenario: Useable item (reward roll)
    """
    Checklist test: Use an item bound to a UseableItem module: it is consumed and a weighted random reward is given.
    """
    When I manually: use an item bound to a UseableItem module with a reward roll
    Then I confirm: the used item is consumed
    And I confirm: I receive a weighted random reward item

  @kora_jobcreator @checklist @checklist:kora_jobcreator:useable-item-recipe @cat:jobs @manual
  Scenario: Useable item (recipe)
    """
    Checklist test: Use an item bound to a recipe: ingredients run through the recipe and output is given; failure refunds the consumed item.
    """
    When I manually: use an item bound to a UseableItem module with a recipe, with all ingredients in my inventory
    Then I confirm: the ingredients are consumed and the recipe output is given
    When I manually: use the item again while missing ingredients so the recipe fails
    Then I confirm: the consumed item is refunded

  @kora_jobcreator @checklist @checklist:kora_jobcreator:card-machine @cat:jobs @manual
  Scenario: Card machine billing
    """
    Checklist test: Employee with cardmachine targets a player and enters an amount; customer approves; bank debited, commission and business account credited.
    """
    When I manually: make sure I have a cardmachine item and am employed at a business, then target a second player with it and enter an amount
    And I manually: ask a second player to approve the payment
    Then I confirm: the other player's bank balance is debited by the amount
    And I confirm: I receive my commission
    And I confirm: the business account is credited

  @kora_jobcreator @checklist @checklist:kora_jobcreator:card-machine-walkaway @cat:jobs @manual
  Scenario: Card machine distance cancel
    """
    Checklist test: Walk away between the two dialogs: the charge is cancelled and nobody is billed.
    """
    When I manually: with a cardmachine in my inventory, target a second player and enter an amount
    And I manually: ask a second player to walk more than 5m away before approving
    Then I confirm: the charge is cancelled
    And I confirm: nobody is billed

  @kora_jobcreator @checklist @checklist:kora_jobcreator:module-blips @cat:jobs @manual
  Scenario: Business blips
    """
    Checklist test: Modules with a blip show it on the map under the Business category (or custom name).
    """
    When I manually: open the map
    Then I confirm: modules with a blip show it under the Business category (or their custom name)

  @kora_jobcreator @checklist @checklist:kora_jobcreator:business-logs @cat:jobs @needs:admin @manual
  Scenario: Activity logs
    """
    Checklist test: Do a sale or craft then check the Activity tab / log table; webhook receives events if configured.
    """
    When I manually: do a sale or a craft at a business
    And I manually: open /jobcreator and the business Activity tab
    Then I confirm: the sale or craft appears in the Activity tab
    And I confirm: the webhook receives the event (only applies when a webhook is configured)
