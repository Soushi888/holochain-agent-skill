use hdk::prelude::*;
use <ZOME_NAME>_integrity::*;

#[derive(Serialize, Deserialize, Debug)]
pub struct AddPostForAgentInput {
    pub base_agent: AgentPubKey,
    pub target_post_hash: ActionHash,
}

#[hdk_extern]
pub fn add_post_for_agent(input: AddPostForAgentInput) -> ExternResult<()> {
    create_link(
        input.base_agent.clone(),
        input.target_post_hash.clone(),
        LinkTypes::AgentToPosts,
        (),
    )?;
    Ok(())
}

#[hdk_extern]
pub fn get_posts_for_agent(agent: AgentPubKey) -> ExternResult<Vec<Link>> {
    get_links(
        LinkQuery::try_new(agent, LinkTypes::AgentToPosts)?,
        GetStrategy::default(),
    )
}

#[hdk_extern]
pub fn get_deleted_posts_for_agent(
    agent: AgentPubKey,
) -> ExternResult<Vec<(SignedActionHashed, Vec<SignedActionHashed>)>> {
    let details = get_links_details(
        LinkQuery::try_new(agent, LinkTypes::AgentToPosts)?,
        GetStrategy::default(),
    )?;
    Ok(details
        .into_inner()
        .into_iter()
        .filter(|(_link, deletes)| !deletes.is_empty())
        .collect())
}

#[derive(Serialize, Deserialize, Debug)]
pub struct RemovePostForAgentInput {
    pub base_agent: AgentPubKey,
    pub target_post_hash: ActionHash,
}

#[hdk_extern]
pub fn delete_post_for_agent(input: RemovePostForAgentInput) -> ExternResult<()> {
    let links = get_links(
        LinkQuery::try_new(input.base_agent.clone(), LinkTypes::AgentToPosts)?,
        GetStrategy::default(),
    )?;
    for link in links {
        if link
            .target
            .clone()
            .into_action_hash()
            .ok_or(wasm_error!(WasmErrorInner::Guest(
                "No action hash associated with link".to_string()
            )))?
            == input.target_post_hash.clone().into_hash()
        {
            delete_link(link.create_link_hash, GetOptions::default())?;
        }
    }
    Ok(())
}
