use holochain::prelude::*;
use holochain::sweettest::*;
use posts::agent_to_posts::*;
use std::path::Path;

mod common;
use common::*;

#[tokio::test(flavor = "multi_thread")]
async fn link_a_agent_to_a_post() {
    // Create conductors with the standard config
    let mut conductors = SweetConductorBatch::standard(2).await;
    let dna_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../workdir/forum.dna");
    let dna_file = SweetDnaFile::from_bundle(&dna_path).await.unwrap();
    let apps = conductors.setup_app("test-app", &[dna_file]).await.unwrap();
    let cells = apps.cells_flattened();
    let alice_conductor = conductors.get(0).unwrap();
    let alice_zome = cells[0].zome("posts");
    let bob_conductor = conductors.get(1).unwrap();
    let bob_zome = cells[1].zome("posts");

    let base_address = alice_zome.cell_id().agent_pubkey().clone();
    let target_record = create_post(&alice_conductor, &alice_zome).await;
    let target_address = target_record.signed_action.hashed.hash.clone();

    // Bob gets the links, should be empty
    let links_output: Vec<Link> = bob_conductor
        .call(&bob_zome, "get_posts_for_agent", base_address.clone())
        .await;
    assert!(links_output.is_empty());

    // Alice creates a link from Agent to Post
    let _: () = alice_conductor
        .call(
            &alice_zome,
            "add_post_for_agent",
            AddPostForAgentInput {
                base_agent: base_address.clone(),
                target_post_hash: target_address.clone(),
            },
        )
        .await;

    await_consistency(&cells).await.unwrap();

    // Bob gets the links again
    let links_output: Vec<Link> = bob_conductor
        .call(&bob_zome, "get_posts_for_agent", base_address.clone())
        .await;
    assert_eq!(links_output.len(), 1);
    assert_eq!(links_output[0].target, target_address.clone().into());

    // Alice deletes the link
    let _: () = alice_conductor
        .call(
            &alice_zome,
            "delete_post_for_agent",
            RemovePostForAgentInput {
                base_agent: base_address.clone(),
                target_post_hash: target_address.clone(),
            },
        )
        .await;

    await_consistency(&cells).await.unwrap();

    // Bob gets the links again
    let links_output: Vec<Link> = bob_conductor
        .call(&bob_zome, "get_posts_for_agent", base_address.clone())
        .await;
    assert!(links_output.is_empty());

    // Bob gets the deleted links
    let deleted_links_output: Vec<(SignedActionHashed, Vec<SignedActionHashed>)> = bob_conductor
        .call(
            &bob_zome,
            "get_deleted_posts_for_agent",
            base_address.clone(),
        )
        .await;
    assert_eq!(deleted_links_output.len(), 1);
}
