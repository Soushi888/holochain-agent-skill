pub mod agent_to_posts;
pub use agent_to_posts::*;
pub mod post;
use hdi::prelude::*;

pub use post::*;

#[derive(Serialize, Deserialize)]
#[serde(tag = "type")]
#[hdk_entry_types]
#[unit_enum(UnitEntryTypes)]
pub enum EntryTypes {
    Post(Post),
}

#[derive(Serialize, Deserialize)]
#[hdk_link_types]
pub enum LinkTypes {
    PostUpdates,
    AgentToPosts,
}

// Validation you perform during the genesis process. Nobody else on the network performs it, only you.
// There *is no* access to network calls in this callback
#[hdk_extern]
pub fn genesis_self_check(_data: GenesisSelfCheckData) -> ExternResult<ValidateCallbackResult> {
    Ok(ValidateCallbackResult::Valid)
}

// Validation the network performs when you try to join, you can't perform this validation yourself as you are not a member yet.
// There *is* access to network calls in this function
pub fn validate_agent_joining(
    _agent_pub_key: AgentPubKey,
    _membrane_proof: &Option<MembraneProof>,
) -> ExternResult<ValidateCallbackResult> {
    Ok(ValidateCallbackResult::Valid)
}

// This is the unified validation callback for all entries and link types in this integrity zome
// Below is a match template for all of the variants of `DHT Ops` and entry and link types
// Holochain has already performed the following validation for you:
// - The action signature matches on the hash of its content and is signed by its author
// - The previous action exists, has a lower timestamp than the new action, and incremented sequence number
// - The previous action author is the same as the new action author
// - The timestamp of each action is after the DNA's origin time
// - AgentActivity authorities check that the agent hasn't forked their chain
// - The entry hash in the action matches the entry content
// - The entry type in the action matches the entry content
// - The entry size doesn't exceed the maximum entry size (currently 4MB)
// - Private entry types are not included in the Op content, and public entry types are
// - If the `Op` is an update or a delete, the original action exists and is a `Create` or `Update` action
// - If the `Op` is an update, the original entry exists and is of the same type as the new one
// - If the `Op` is a delete link, the original action exists and is a `CreateLink` action
// - Link tags don't exceed the maximum tag size (currently 1KB)
// - Countersigned entries include an action from each required signer
// You can read more about validation here: https://docs.rs/hdi/latest/hdi/index.html#data-validation
#[hdk_extern]
pub fn validate(op: Op) -> ExternResult<ValidateCallbackResult> {
    match op.flattened::<EntryTypes, LinkTypes>()? {
        FlatOp::CreateEntry(create_entry) => match create_entry {
            OpEntry::CreateEntry { app_entry, action } => {
                let action: Action = action.into();
                let create_action: Result<TypedAction<EntryCreationData>, WrongActionError> =
                    action.try_into();
                let create_action =
                    create_action.map_err(|e| wasm_error!(WasmErrorInner::Guest(e.to_string())))?;
                match app_entry {
                    EntryTypes::Post(post) => validate_create_post(create_action, post),
                }
            }
            OpEntry::UpdateEntry {
                app_entry, action, ..
            } => {
                let action: Action = action.into();
                let create_action: Result<TypedAction<EntryCreationData>, WrongActionError> =
                    action.try_into();
                let create_action =
                    create_action.map_err(|e| wasm_error!(WasmErrorInner::Guest(e.to_string())))?;
                match app_entry {
                    EntryTypes::Post(post) => validate_create_post(create_action, post),
                }
            }
            _ => Ok(ValidateCallbackResult::Valid),
        },
        FlatOp::Update(update_entry) => match update_entry {
            OpUpdate::Entry { app_entry, action } => {
                let original_action = must_get_action(action.data.original_action_address.clone())?
                    .action()
                    .to_owned();
                let original_action: Result<TypedAction<EntryCreationData>, WrongActionError> =
                    original_action.try_into();
                let original_action = original_action
                    .map_err(|e| wasm_error!(WasmErrorInner::Guest(e.to_string())))?;
                match app_entry {
                    EntryTypes::Post(post) => {
                        let original_app_entry =
                            must_get_valid_record(action.data.original_action_address.clone())?;
                        let original_post = match Post::try_from(original_app_entry) {
                            Ok(entry) => entry,
                            Err(e) => {
                                return Ok(ValidateCallbackResult::Invalid(format!(
                                    "Expected to get Post from Record: {e:?}"
                                )));
                            }
                        };
                        validate_update_post(action, post, original_action, original_post)
                    }
                }
            }
            _ => Ok(ValidateCallbackResult::Valid),
        },
        FlatOp::Delete(OpDelete { action }) => {
            let original_record = must_get_valid_record(action.data.deletes_address.clone())?;
            let original_record_action = original_record.action().clone();
            let original_action: Result<TypedAction<EntryCreationData>, WrongActionError> =
                original_record_action.try_into();
            let original_action =
                original_action.map_err(|e| wasm_error!(WasmErrorInner::Guest(e.to_string())))?;
            let app_entry_type = match original_action.entry_type() {
                EntryType::App(app_entry_type) => app_entry_type,
                _ => {
                    return Ok(ValidateCallbackResult::Valid);
                }
            };
            let entry = match original_record.entry().as_option() {
                Some(entry) => entry,
                None => {
                    return Ok(ValidateCallbackResult::Invalid(
                        "Original record for a delete must contain an entry".to_string(),
                    ));
                }
            };
            let original_app_entry = match EntryTypes::deserialize_from_type(
                app_entry_type.zome_index,
                app_entry_type.entry_index,
                entry,
            )? {
                Some(app_entry) => app_entry,
                None => {
                    return Ok(ValidateCallbackResult::Invalid(
                        "Original app entry must be one of the defined entry types for this zome"
                            .to_string(),
                    ));
                }
            };
            match original_app_entry {
                EntryTypes::Post(original_post) => {
                    validate_delete_post(action, original_action, original_post)
                }
            }
        }
        FlatOp::Link(OpLink::CreateLink { link_type, action }) => match link_type {
            LinkTypes::PostUpdates => validate_create_link_post_updates(action),
            LinkTypes::AgentToPosts => validate_create_link_agent_to_posts(action),
        },
        FlatOp::Link(OpLink::DeleteLink {
            link_type,
            original_action,
            action,
        }) => match link_type {
            LinkTypes::PostUpdates => validate_delete_link_post_updates(action, original_action),
            LinkTypes::AgentToPosts => validate_delete_link_agent_to_posts(action, original_action),
        },
        FlatOp::CreateRecord(store_record) => {
            match store_record {
                // Complementary validation to the `CreateEntry` Op, in which the record itself is validated
                // If you want to optimize performance, you can remove the validation for an entry type here and keep it in `CreateEntry`
                // Notice that doing so will cause `must_get_valid_record` for this record to return a valid record even if the `CreateEntry` validation failed
                OpRecord::CreateEntry { app_entry, action } => {
                    let action: Action = action.into();
                    let action: Result<TypedAction<EntryCreationData>, WrongActionError> =
                        action.try_into();
                    let action =
                        action.map_err(|e| wasm_error!(WasmErrorInner::Guest(e.to_string())))?;
                    match app_entry {
                        EntryTypes::Post(post) => validate_create_post(action, post),
                    }
                }
                // Complementary validation to the `Update` Op, in which the record itself is validated
                // If you want to optimize performance, you can remove the validation for an entry type here and keep it in `CreateEntry` and in `Update`
                // Notice that doing so will cause `must_get_valid_record` for this record to return a valid record even if the other validations failed
                OpRecord::UpdateEntry {
                    app_entry, action, ..
                } => {
                    let original_record =
                        must_get_valid_record(action.data.original_action_address.clone())?;
                    let original_action = original_record.action().clone();
                    let original_action: Result<TypedAction<EntryCreationData>, WrongActionError> =
                        original_action.try_into();
                    let original_action = original_action
                        .map_err(|e| wasm_error!(WasmErrorInner::Guest(e.to_string())))?;
                    let creation_action: Action = action.clone().into();
                    let creation_action: Result<TypedAction<EntryCreationData>, WrongActionError> =
                        creation_action.try_into();
                    let creation_action = creation_action
                        .map_err(|e| wasm_error!(WasmErrorInner::Guest(e.to_string())))?;
                    match app_entry {
                        EntryTypes::Post(post) => {
                            let result = validate_create_post(creation_action, post.clone())?;
                            if let ValidateCallbackResult::Valid = result {
                                let original_post: Option<Post> = original_record
                                    .entry()
                                    .to_app_option()
                                    .map_err(|e| wasm_error!(e))?;
                                let original_post = match original_post {
                                    Some(post) => post,
                                    None => {
                                        return Ok(
                                            ValidateCallbackResult::Invalid(
                                                "The updated entry type must be the same as the original entry type"
                                                    .to_string(),
                                            ),
                                        );
                                    }
                                };
                                validate_update_post(action, post, original_action, original_post)
                            } else {
                                Ok(result)
                            }
                        }
                    }
                }
                // Complementary validation to the `Delete` Op, in which the record itself is validated
                // If you want to optimize performance, you can remove the validation for an entry type here and keep it in `Delete`
                // Notice that doing so will cause `must_get_valid_record` for this record to return a valid record even if the `Delete` validation failed
                OpRecord::DeleteEntry { action, .. } => {
                    let original_record =
                        must_get_valid_record(action.data.deletes_address.clone())?;
                    let original_action = original_record.action().clone();
                    let original_action: Result<TypedAction<EntryCreationData>, WrongActionError> =
                        original_action.try_into();
                    let original_action = original_action
                        .map_err(|e| wasm_error!(WasmErrorInner::Guest(e.to_string())))?;
                    let app_entry_type = match original_action.entry_type() {
                        EntryType::App(app_entry_type) => app_entry_type,
                        _ => {
                            return Ok(ValidateCallbackResult::Valid);
                        }
                    };
                    let entry = match original_record.entry().as_option() {
                        Some(entry) => entry,
                        None => {
                            return Ok(ValidateCallbackResult::Invalid(
                                "Original record for a delete must contain an entry".to_string(),
                            ));
                        }
                    };
                    let original_app_entry = match EntryTypes::deserialize_from_type(
                        app_entry_type.zome_index,
                        app_entry_type.entry_index,
                        entry,
                    )? {
                        Some(app_entry) => app_entry,
                        None => {
                            return Ok(
                                ValidateCallbackResult::Invalid(
                                    "Original app entry must be one of the defined entry types for this zome"
                                        .to_string(),
                                ),
                            );
                        }
                    };
                    match original_app_entry {
                        EntryTypes::Post(original_post) => {
                            validate_delete_post(action, original_action, original_post)
                        }
                    }
                }
                // Complementary validation to the `Link(OpLink::CreateLink { .. })` Op, in which the record itself is validated
                // If you want to optimize performance, you can remove the validation for a link type here and keep it in `Link`
                // Notice that doing so will cause `must_get_valid_record` for this record to return a valid record even if the `Link` validation failed
                OpRecord::CreateLink { link_type, action } => match link_type {
                    LinkTypes::PostUpdates => validate_create_link_post_updates(action),
                    LinkTypes::AgentToPosts => validate_create_link_agent_to_posts(action),
                },
                // Complementary validation to the `Link(OpLink::DeleteLink { .. })` Op, in which the record itself is validated
                // If you want to optimize performance, you can remove the validation for a link type here and keep it in `Link`
                // Notice that doing so will cause `must_get_valid_record` for this record to return a valid record even if the `Link` validation failed
                OpRecord::DeleteLink { action } => {
                    let record = must_get_valid_record(action.data.link_add_address.clone())?;
                    let create_link = match &record.action().data {
                        ActionData::CreateLink(create_link) => TypedAction {
                            header: record.action().header.clone(),
                            data: create_link.clone(),
                        },
                        _ => {
                            return Ok(ValidateCallbackResult::Invalid(
                                "The action that a DeleteLink deletes must be a CreateLink"
                                    .to_string(),
                            ));
                        }
                    };
                    let link_type = match LinkTypes::from_type(
                        create_link.data.zome_index,
                        create_link.data.link_type,
                    )? {
                        Some(lt) => lt,
                        None => {
                            return Ok(ValidateCallbackResult::Valid);
                        }
                    };
                    match link_type {
                        LinkTypes::PostUpdates => {
                            validate_delete_link_post_updates(action, create_link)
                        }
                        LinkTypes::AgentToPosts => {
                            validate_delete_link_agent_to_posts(action, create_link)
                        }
                    }
                }
                OpRecord::CreatePrivateEntry { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::UpdatePrivateEntry { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::CreateCapClaim { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::CreateCapGrant { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::UpdateCapClaim { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::UpdateCapGrant { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::Dna { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::OpenChain { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::CloseChain { .. } => Ok(ValidateCallbackResult::Valid),
                OpRecord::InitZomesComplete { .. } => Ok(ValidateCallbackResult::Valid),
                _ => Ok(ValidateCallbackResult::Valid),
            }
        }
        FlatOp::AgentActivity(agent_activity) => match agent_activity {
            OpActivity::CreateAgent { agent, action } => {
                let prev = action
                    .prev_action()
                    .ok_or_else(|| {
                        wasm_error!(WasmErrorInner::Guest("expected a prior action".into()))
                    })?
                    .clone();
                let previous_action = must_get_action(prev)?;
                match &previous_action.action().data {
                        ActionData::AgentValidationPkg(
                            AgentValidationPkgData { membrane_proof, .. },
                        ) => validate_agent_joining(agent, membrane_proof),
                        _ => {
                            Ok(
                                ValidateCallbackResult::Invalid(
                                    "The previous action for a `CreateAgent` action must be an `AgentValidationPkg`"
                                        .to_string(),
                                ),
                            )
                        }
                    }
            }
            _ => Ok(ValidateCallbackResult::Valid),
        },
    }
}
