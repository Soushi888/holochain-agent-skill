use holochain::prelude::*;
use holochain::sweettest::*;
use <ZOME_NAME>::<entry_type>::*;
use <ZOME_NAME>_integrity::*;
use std::path::Path;

mod common;
use common::*;

#[tokio::test(flavor = "multi_thread")]
async fn create_post() {
    // Create a conductor with the standard config
    let mut conductor = SweetConductor::standard().await;
    let dna_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../workdir/<DNA_NAME>.dna");
    let dna_file = SweetDnaFile::from_bundle(&dna_path).await.unwrap();
    let app = conductor.setup_app("test-app", &[dna_file]).await.unwrap();
    let zome = app.cells()[0].zome("<ZOME_NAME>");

    let <entry_type> = sample_post(&conductor, &zome).await;

    // Agent creates a <EntryType>
    let _: Record = conductor.call(&zome, "create_post", <entry_type>.clone()).await;
}

#[tokio::test(flavor = "multi_thread")]
async fn create_and_read_post() {
    // Create conductors with the standard config
    let mut conductors = SweetConductorBatch::standard(2).await;
    let dna_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../workdir/<DNA_NAME>.dna");
    let dna_file = SweetDnaFile::from_bundle(&dna_path).await.unwrap();
    let apps = conductors.setup_app("test-app", &[dna_file]).await.unwrap();
    let cells = apps.cells_flattened();
    let alice_conductor = conductors.get(0).unwrap();
    let alice_zome = cells[0].zome("<ZOME_NAME>");
    let bob_conductor = conductors.get(1).unwrap();
    let bob_zome = cells[1].zome("<ZOME_NAME>");

    let <entry_type> = sample_post(&alice_conductor, &alice_zome).await;

    // Alice creates a <EntryType>
    let record: Record = alice_conductor
        .call(&alice_zome, "create_post", <entry_type>.clone())
        .await;

    // Wait for the created entry to be propagated to the other node.
    await_consistency(&cells).await.unwrap();

    // Bob gets the created <EntryType>
    let propagated_record: Record = bob_conductor
        .call(
            &bob_zome,
            "get_original_post",
            record.signed_action.hashed.hash.clone(),
        )
        .await;
    assert_eq!(record, propagated_record);
}

#[tokio::test(flavor = "multi_thread")]
async fn create_and_update_post() {
    // Create conductors with the standard config
    let mut conductors = SweetConductorBatch::standard(2).await;
    let dna_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../workdir/<DNA_NAME>.dna");
    let dna_file = SweetDnaFile::from_bundle(&dna_path).await.unwrap();
    let apps = conductors.setup_app("test-app", &[dna_file]).await.unwrap();
    let cells = apps.cells_flattened();
    let alice_conductor = conductors.get(0).unwrap();
    let alice_zome = cells[0].zome("<ZOME_NAME>");
    let bob_conductor = conductors.get(1).unwrap();
    let bob_zome = cells[1].zome("<ZOME_NAME>");

    let <entry_type> = sample_post(&alice_conductor, &alice_zome).await;

    // Alice creates a <EntryType>
    let record: Record = alice_conductor
        .call(&alice_zome, "create_post", <entry_type>.clone())
        .await;

    let original_action_hash = record.signed_action.hashed.hash.clone();

    // Alice updates the <EntryType>
    let content_update = sample_post(&alice_conductor, &alice_zome).await;
    let update_input = UpdatePostInput {
        original_post_hash: original_action_hash.clone(),
        previous_post_hash: original_action_hash.clone(),
        updated_post: content_update.clone(),
    };
    let updated_record: Record = alice_conductor
        .call(&alice_zome, "update_post", update_input)
        .await;

    // Wait for the updated entry to be propagated to the other node.
    await_consistency(&cells).await.unwrap();

    // Bob gets the updated <EntryType>
    let read_updated_record_1: Record = bob_conductor
        .call(
            &bob_zome,
            "get_latest_post",
            updated_record.signed_action.hashed.hash.clone(),
        )
        .await;
    assert_eq!(updated_record, read_updated_record_1);

    // Alice updates the <EntryType> again
    let content_update = sample_post(&alice_conductor, &alice_zome).await;
    let update_input = UpdatePostInput {
        original_post_hash: original_action_hash.clone(),
        previous_post_hash: updated_record.signed_action.hashed.hash.clone(),
        updated_post: content_update.clone(),
    };
    let updated_record: Record = alice_conductor
        .call(&alice_zome, "update_post", update_input)
        .await;

    // Wait for the updated entry to be propagated to the other node.
    await_consistency(&cells).await.unwrap();

    // Bob gets the updated <EntryType>
    let read_updated_record_2: Record = bob_conductor
        .call(
            &bob_zome,
            "get_latest_post",
            updated_record.signed_action.hashed.hash.clone(),
        )
        .await;
    let RecordEntry::Present(entry) = read_updated_record_2.entry else {
        panic!(
            "Expected Present entry, got {:?}",
            read_updated_record_2.entry
        );
    };
    assert_eq!(<EntryType>::try_from(entry.clone()).unwrap(), content_update);

    // Bob gets all the revisions for <EntryType>
    let revisions: Vec<Record> = bob_conductor
        .call(
            &bob_zome,
            "get_all_revisions_for_post",
            original_action_hash,
        )
        .await;
    assert_eq!(revisions.len(), 3);
    let RecordEntry::Present(ref entry) = revisions[2].entry else {
        panic!("Expected Present entry, got {:?}", revisions[2].entry);
    };
    assert_eq!(<EntryType>::try_from(entry).unwrap(), content_update);
}

#[tokio::test(flavor = "multi_thread")]
async fn create_and_delete_post() {
    // Create conductors with the standard config
    let mut conductors = SweetConductorBatch::standard(2).await;
    let dna_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../workdir/<DNA_NAME>.dna");
    let dna_file = SweetDnaFile::from_bundle(&dna_path).await.unwrap();
    let apps = conductors.setup_app("test-app", &[dna_file]).await.unwrap();
    let cells = apps.cells_flattened();
    let alice_conductor = conductors.get(0).unwrap();
    let alice_zome = cells[0].zome("<ZOME_NAME>");
    let bob_conductor = conductors.get(1).unwrap();
    let bob_zome = cells[1].zome("<ZOME_NAME>");

    let <entry_type> = sample_post(&alice_conductor, &alice_zome).await;

    // Alice creates a <EntryType>
    let record: Record = alice_conductor
        .call(&alice_zome, "create_post", <entry_type>.clone())
        .await;

    // Wait for the created entry to be propagated to the other node.
    await_consistency(&cells).await.unwrap();

    // Alice deletes the <EntryType>
    let _delete_action_hash: ActionHash = alice_conductor
        .call(
            &alice_zome,
            "delete_post",
            record.signed_action.hashed.hash.clone(),
        )
        .await;

    // Wait for the entry deletion to be propagated to the other node.
    await_consistency(&cells).await.unwrap();

    // Bob gets the oldest delete for the <EntryType>
    let oldest_delete_for_post: Option<SignedActionHashed> = bob_conductor
        .call(
            &bob_zome,
            "get_oldest_delete_for_post",
            record.signed_action.hashed.hash.clone(),
        )
        .await;
    assert!(oldest_delete_for_post.is_some());

    // Bob gets the deletions for the <EntryType>
    let deletes_for_post: Option<Vec<SignedActionHashed>> = bob_conductor
        .call(
            &bob_zome,
            "get_all_deletes_for_post",
            record.signed_action.hashed.hash.clone(),
        )
        .await;
    assert_eq!(deletes_for_post.unwrap().len(), 1);
}
